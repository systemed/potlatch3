package net.systemeD.potlatch2.controller {
	import flash.events.*;
	import flash.geom.Point;
	import flash.ui.Keyboard;
	
	import net.systemeD.halcyon.AttentionEvent;
	import net.systemeD.halcyon.WayUI;
	import net.systemeD.halcyon.connection.*;
	import net.systemeD.halcyon.connection.actions.*;
	import net.systemeD.potlatch2.tools.Quadrilateralise;

    public class SelectedWayNode extends SelectedNode {
		private var parentWay:Way;
		private var initIndex:int;
		private var selectedIndex:int;
		private var shiftClickEvent:MouseEvent;
        
        public function SelectedWayNode(way:Way,index:int) {
            parentWay = way;
			initIndex = index;
        }

		override public function handleShiftClickOnEntry(event:MouseEvent):void {
			shiftClickEvent=event;
		}

        protected function selectNode(way:Way,index:int):void {
			var node:Node=way.getNode(index);
            if ( way == parentWay && node == firstSelected )
                return;

            clearSelection(this);
            layer.setHighlight(way, { hover: false });
            layer.setHighlight(node, { selected: true });
            layer.setHighlightOnNodes(way, { selectedway: true });
            selection = [node]; parentWay = way;
            controller.updateSelectionUI();
			selectedIndex = index; initIndex = index;
        }
                
        protected function clearSelection(newState:ControllerState):void {
            if ( selectCount ) {
            	layer.setHighlight(parentWay, { selected: false });
				layer.setHighlight(firstSelected, { selected: false });
				layer.setHighlightOnNodes(parentWay, { selectedway: false });
				selection = [];
                if (!newState.isSelectionState()) { controller.updateSelectionUI(); }
            }
        }
        
        override public function processMouseEvent(event:MouseEvent, entity:Entity):ControllerState {
			if (event.type==MouseEvent.MOUSE_MOVE || event.type==MouseEvent.ROLL_OVER || event.type==MouseEvent.MOUSE_OUT) { return this; }
            var focus:Entity = getTopLevelFocusEntity(entity);

            if ( event.type == MouseEvent.MOUSE_UP && entity is Node && event.shiftKey ) {
				// start new way
                var way:Way = entity.connection.createWay({}, [entity],
                    MainUndoStack.getGlobalStack().addAction);
                return new DrawWay(way, true, false);
			} else if ( event.type == MouseEvent.MOUSE_UP && entity is Node && focus == parentWay ) {
				// select node within way
				return selectOrEdit(parentWay, getNodeIndex(parentWay,Node(entity)));
            } else if ( event.type == MouseEvent.MOUSE_DOWN && entity is Way && focus==parentWay && event.shiftKey) {
				// insert node within way (shift-click)
          		var d:DragWayNode=new DragWayNode(parentWay, -1, event, true);
				d.forceDragStart();
				return d;
			} else if ( event.type == MouseEvent.MOUSE_UP && !entity && event.shiftKey ) {
				// shift-clicked nearby to insert node
				var lat:Number = controller.map.coord2lat(event.localY);
				var lon:Number = controller.map.coord2lon(event.localX);
				var undo:CompositeUndoableAction = new CompositeUndoableAction("Insert node");
				parentWay.insertNodeOrMoveExisting(lat, lon, undo.push);
				MainUndoStack.getGlobalStack().addAction(undo);
				return new SelectedWay(parentWay);
			}
			var cs:ControllerState = sharedMouseEvents(event, entity);
			return cs ? cs : this;
        }

		override public function processKeyboardEvent(event:KeyboardEvent):ControllerState {
			switch (event.keyCode) {
				case 189:					return removeNode();					// '-'
				case 88:					return splitWay();						// 'X'
				case 78:					return otherEnd();						// 'N'
				case 79:					return replaceNode();					// 'O'
                case 81:  /* Q */           Quadrilateralise.quadrilateralise(parentWay, MainUndoStack.getGlobalStack().addAction); return this;
                case 82:  /* R */           { if (! event.shiftKey) repeatTags(firstSelected); 
                                              else                  repeatRelations(firstSelected);
                                              return this; }
				case 87:					return new SelectedWay(parentWay);		// 'W'
				case 191:					return cycleWays();						// '/'
                case 74:                    if (event.shiftKey) { return unjoin() }; return join();// 'J'
				case Keyboard.BACKSPACE:	return deleteNode();
				case Keyboard.DELETE:		return deleteNode();
				case 188: /* , */           return stepNode(event.shiftKey ? -10 : -1);
				case 190: /* . */           return stepNode(event.shiftKey ? +10 : +1);
			}
			var cs:ControllerState = sharedKeyboardEvents(event);
			return cs ? cs : this;
		}

		override public function get selectedWay():Way {
			return parentWay;
		}

		override public function get selectedNode():Node {
			return parentWay.getNode(selectedIndex);
		}
        
		private function cycleWays():ControllerState {
			var wayList:Array=firstSelected.parentWays;
			if (wayList.length==1) { return this; }
			wayList.splice(wayList.indexOf(parentWay),1);
            // find index of this node in the newly selected way, to maintain state for keyboard navigation
            var newindex:int = Way(wayList[0]).indexOfNode(parentWay.getNode(initIndex));
			return new SelectedWay(wayList[0], layer,
			                       new Point(controller.map.lon2coord(Node(firstSelected).lon),
			                                 controller.map.latp2coord(Node(firstSelected).latp)),
			                       wayList.concat(parentWay),
			                       newindex);
		}

		override public function enterState():void {
			if (shiftClickEvent) {
				// previously shift-clicked nearby to insert node, passed through by ZoomArea
				var lat:Number = controller.map.coord2lat(shiftClickEvent.localY);
				var lon:Number = controller.map.coord2lon(shiftClickEvent.localX);
				var undo:CompositeUndoableAction = new CompositeUndoableAction("Insert node");
				parentWay.insertNodeOrMoveExisting(lat, lon, undo.push);
				MainUndoStack.getGlobalStack().addAction(undo);
				shiftClickEvent = null;
			}
            selectNode(parentWay,initIndex);
			layer.setPurgable(selection,false);
        }
		override public function exitState(newState:ControllerState):void {
            if (firstSelected.hasTags()) {
              controller.clipboards['node']=firstSelected.getTagsCopy();
            }
            copyRelations(firstSelected);
			layer.setPurgable(selection,true);
            clearSelection(newState);
        }

        override public function toString():String {
            return "SelectedWayNode";
        }

		public static function selectOrEdit(selectedWay:Way, index:int):ControllerState {
			var isFirst:Boolean = false;
			var isLast:Boolean = false;
			var node:Node = selectedWay.getNode(index);
			isFirst = selectedWay.getNode(0) == node;
			isLast = selectedWay.getLastNode() == node;
			if ( isFirst == isLast )    // both == looped, none == central node 
			    return new SelectedWayNode(selectedWay, index);
			else
			    return new DrawWay(selectedWay, isLast, true);
        }

		/** Replace the selected node with a new one created at the mouse position. 
			The undo for this is two actions: first, replacement of the old node at the original mouse position; then, moving to the new position.
			It's debatable whether this should be one or two but we can leave it as a FIXME for now.  */
		public function replaceNode():ControllerState {
			// replace old node
			var oldNode:Node=firstSelected as Node;
			var newNode:Node=oldNode.replaceWithNew(layer.connection,
			                                        controller.map.coord2lat(layer.mouseY), 
			                                        controller.map.coord2lon(layer.mouseX), {},
			                                        MainUndoStack.getGlobalStack().addAction);

			// start dragging
			// we fake a MouseEvent because DragWayNode expects the x/y co-ords to be passed that way
			var d:DragWayNode=new DragWayNode(parentWay, parentWay.indexOfNode(newNode), new MouseEvent(MouseEvent.CLICK, true, false, layer.mouseX, layer.mouseY), true);
			d.forceDragStart();
			return d;
		}

		/** Splits a way into two separate ways, at the currently selected node. Handles simple loops and P-shapes. Untested for anything funkier. */
		public function splitWay():ControllerState {
			var n:Node=firstSelected as Node;
			var ni:uint = parentWay.indexOfNode(n);
			// abort if start or end
			if (parentWay.isPShape() && !parentWay.hasOnceOnly(n)) {
				// If P-shaped, we want to split at the midway point on the stem, not at the end of the loop
				ni = parentWay.getPJunctionNodeIndex();
				
			} else {
			    if (parentWay.getNode(0)    == n) { return this; }
			    if (parentWay.getLastNode() == n) { return this; }
			}

			layer.setHighlightOnNodes(parentWay, { selectedway: false } );
			layer.setPurgable([parentWay],true);
            MainUndoStack.getGlobalStack().addAction(new SplitWayAction(parentWay, ni));

			return new SelectedWay(parentWay);
		}
		
		public function removeNode():ControllerState {
			if (firstSelected.numParentWays==1 && parentWay.hasOnceOnly(firstSelected as Node) && !(firstSelected as Node).hasInterestingTags()) {
				return deleteNode();
			}
			parentWay.removeNodeByIndex(selectedIndex, MainUndoStack.getGlobalStack().addAction);
			return new SelectedWay(parentWay);
		}
		
		public function deleteNode():ControllerState {
			layer.setPurgable(selection,true);
			firstSelected.remove(MainUndoStack.getGlobalStack().addAction);
			return new SelectedWay(parentWay);
		}

        public function unjoin():ControllerState {
            Node(firstSelected).unjoin(parentWay, MainUndoStack.getGlobalStack().addAction);
            return this;
        }

		/** Move the selection one node further up or down this way, looping if necessary. */
		public function stepNode(delta:int):ControllerState {
			var ni:int;
			if (Math.abs(delta)==1) {
				ni = (selectedIndex + delta + parentWay.length) % parentWay.length;
			} else if (delta<0) {
				ni = Math.max(selectedIndex+delta, 0);
			} else {
				ni = Math.min(selectedIndex+delta, parentWay.length-1);
			}
			controller.map.scrollIfNeeded(parentWay.getNode(ni).lat,parentWay.getNode(ni).lon);
			return new SelectedWayNode(parentWay, ni);
		}

		/** Jump to the other end of the way **/
		public function otherEnd():ControllerState {
			var n:Node = parentWay.getFirstNode().within(map.edge_l, map.edge_r, map.edge_t, map.edge_b) ? parentWay.getLastNode() : parentWay.getFirstNode();
           	controller.map.scrollIfNeeded(n.lat,n.lon);
			return new SelectedWay(parentWay);
		}

    }
    
    
}

