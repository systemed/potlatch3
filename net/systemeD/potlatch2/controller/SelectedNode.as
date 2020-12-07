package net.systemeD.potlatch2.controller {
	import flash.events.*;
	import flash.geom.Point;
	import flash.ui.Keyboard;
	
	import net.systemeD.halcyon.AttentionEvent;
	import net.systemeD.halcyon.WayUI;
	import net.systemeD.halcyon.connection.*;
	import net.systemeD.halcyon.connection.actions.*;

	/* Base class for SelectedPOINode / SelectedWayNode. Do not instantiate this in itself. */

    public class SelectedNode extends ControllerState {

		// Stubs to be overwritten
		public function get selectedNode():Node { return null; }

        /** Attempt to either merge the currently selected node with another very nearby node, or failing that,
        *   attach it mid-way along a very nearby way. */
		// FIXME: why are we only merging one node at once? after all, shift-click to insert a node adds into all ways
        public function join():ControllerState {
			var p:Point = new Point(controller.map.lon2coord(Node(firstSelected).lon),
			                        controller.map.latp2coord(Node(firstSelected).latp));
            var q:Point = map.localToGlobal(p);

            // First, look for POI nodes in 20x20 pixel box around the current node
			// FIXME: why aren't we using a hitTest for this?
            var hitnodes:Array = layer.connection.getObjectsByBbox(
                map.coord2lon(p.x-10),
                map.coord2lon(p.x+10),
                map.coord2lat(p.y-10),
                map.coord2lat(p.y+10)).poisInside;
            
            for each (var n: Node in hitnodes) {
                if (!n.hasParent(selectedWay) && n!=selectedNode) { 
                   return doMergeNodes(n);
                }
            }
            
			var ways:Array=layer.findWaysAtPoint(q.x, q.y, selectedWay);
			for each (var w:Way in ways) {
                // hit a way, now let's see if we hit a specific node
                for (var i:uint = 0; i < w.length; i++) {
					n = w.getNode(i);
					var x:Number = map.lon2coord(n.lon);
					var y:Number = map.latp2coord(n.latp);
					if (n != selectedNode && Math.abs(x-p.x) + Math.abs(y-p.y) < 10) {
						return doMergeNodes(n);
					}
				}
            }

            // No nodes hit, so join our node onto any overlapping ways.
            Node(firstSelected).join(ways,MainUndoStack.getGlobalStack().addAction);
            return this;
        }

        private function doMergeNodes(n:Node): ControllerState {
        	var nways:Array = n.parentWays.concat(Node(firstSelected).parentWays);
        	var mna:MergeNodesAction = n.mergeWith(Node(firstSelected), MainUndoStack.getGlobalStack().addAction);
            /* Duplicated consecutive nodes happen if the two merged nodes are consecutive nodes of a (different) way */
            for each (var w:Way in nways) {
               // If there's a node to remove, jam that action into the existing MergeNodesAction. 
               w.removeRepeatedNodes(function (a:UndoableAction):void { a.doAction(); mna.push(a); } );
            }
               
            // only merge one node at a time - too confusing otherwise?
            var msg:String = "Nodes merged"
            if (MergeNodesAction.lastTagsMerged) msg += ": check conflicting tags";
            controller.dispatchEvent(new AttentionEvent(AttentionEvent.ALERT, null, msg));
			if (n.isDeleted()) n=Node(firstSelected);
            return new SelectedWayNode(n.parentWays[0], Way(n.parentWays[0]).indexOfNode(n));
        }
	}
}
