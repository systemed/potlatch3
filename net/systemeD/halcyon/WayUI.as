package net.systemeD.halcyon {

	import flash.display.*;
	import flash.events.*;
	import flash.geom.Matrix;
	import flash.geom.Rectangle;
	import flash.system.Capabilities;
	import flash.text.TextField;
	import flash.text.TextFormat;
	
	import net.systemeD.halcyon.connection.*;
	import net.systemeD.halcyon.styleparser.*;
    import net.systemeD.halcyon.FileBank;

	/** The graphical representation of a Way. */ 
	public class WayUI extends EntityUI {

		/** Total length of way */
		public var pathlength:Number;
		/** Area of the way */
		public var patharea:Number;
		/** X coord of the centre of the area */
		public var centroid_x:Number;
		/** Y coord of the centre of the area */
		public var centroid_y:Number;				//  |
		/** Angle at each node */
		public var heading:Array=new Array();
		/** Is this only partially drawn? */
		public var partial:Boolean=false;
		/** vertex to draw exclusively, or not at all (used by DragWayNode) */ 
		public var drawExcept:Number;
		/** " */
		public var drawOnly:Number;
		private var indexStart:uint;
		private var indexEnd:uint;
		public var nameformat:TextFormat;
		private var recalculateDue:Boolean=false;
		// Store the temporary highlight settings applied to all nodes.
		private var nodehighlightsettings: Object={};

		private const NODESIZE:uint=6;

		public function WayUI(way:Way, paint:MapPaint) {
			super(way,paint);
            entity.addEventListener(Connection.WAY_NODE_ADDED, wayNodeAdded, false, 0, true);
            entity.addEventListener(Connection.WAY_NODE_REMOVED, wayNodeRemoved, false, 0, true);
            entity.addEventListener(Connection.WAY_REORDERED, wayReordered, false, 0, true);
            entity.addEventListener(Connection.ENTITY_DRAGGED, wayDragged, false, 0, true);
            attachNodeListeners();
            attachRelationListeners();
            recalculate();
			redraw();
			redrawMultis();
		}
		
		public function removeEventListeners():void {
			removeGenericEventListeners();
            entity.removeEventListener(Connection.WAY_NODE_ADDED, wayNodeAdded);
            entity.removeEventListener(Connection.WAY_NODE_REMOVED, wayNodeRemoved);
            entity.removeEventListener(Connection.WAY_REORDERED, wayReordered);
            entity.removeEventListener(Connection.ENTITY_DRAGGED, wayDragged);
			removeNodeListeners();
			removeRelationListeners();
		}
		
		private function attachNodeListeners():void {
			var way:Way=entity as Way;
            for (var i:uint = 0; i < way.length; i++ ) {
                way.getNode(i).addEventListener(Connection.NODE_MOVED, nodeMoved, false, 0, true);
            }
		}
		
		private function removeNodeListeners():void {
			var way:Way=entity as Way;
            for (var i:uint = 0; i < way.length; i++ ) {
                way.getNode(i).removeEventListener(Connection.NODE_MOVED, nodeMoved);
            }
		}
		
		private function wayNodeAdded(event:WayNodeEvent):void {
		    event.node.addEventListener(Connection.NODE_MOVED, nodeMoved, false, 0, true);
            recalculate();
		    redraw();
			redrawMultis();
			updateHighlights();
		}
		    
		private function wayNodeRemoved(event:WayNodeEvent):void {
		    if (!event.node.hasParent(event.way)) {
				event.node.removeEventListener(Connection.NODE_MOVED, nodeMoved);
			}
			paint.redrawEntity(event.node);
            recalculate();
		    redraw();
			redrawMultis();
		}
		    
        private function nodeMoved(event:NodeMovedEvent):void {
			recalculate();
            redraw();
			redrawMultis();
        }
        private function wayReordered(event:EntityEvent):void {
            redraw();
			redrawMultis();
        }
		private function wayDragged(event:EntityDraggedEvent):void {
			offsetSprites(event.xDelta,event.yDelta);
		}

		override protected function relationAdded(event:RelationMemberEvent):void {
			super.relationAdded(event);
			redrawMultis();
		}
		override protected function relationRemoved(event:RelationMemberEvent):void {
			super.relationRemoved(event);
			redrawMultis();
		}
		override protected function relationTagChanged(event:TagEvent):void {
			super.relationTagChanged(event);
			redrawMultis();
		}

		/** Don't redraw until further notice. */
		override public function suspendRedraw(event:EntityEvent):void {
			super.suspendRedraw(event);
			recalculateDue=false;
		}
		
		/** Continue redrawing as normal. */
		override public function resumeRedraw(event:EntityEvent):void {
			suspended=false;
			if (recalculateDue) { recalculate(); }
			super.resumeRedraw(event);
		}

		/** Redraw other ways that are the "outer" part of a multipolygon of which we are the "inner" */
		public function redrawMultis():void {
			var multis:Array=entity.findParentRelationsOfType('multipolygon','inner');
			for each (var m:Relation in multis) {
				var outers:Array=m.findMembersByRole('outer');
				for each (var e:Entity in outers) { 
					paint.redrawEntity(e);
				}
			}
		}
        
        /** Mark every node in this way as highlighted, and redraw it. 
        * 
        * @param settings Style state that it applies to. @see EntityUI#setStateClass()
        *  */
        public function setHighlightOnNodes(settings:Object):void {
			for (var i:uint = 0; i < Way(entity).length; i++) {
                var node:Node = Way(entity).getNode(i);
				// Speed things up a bit by only setting the highlight if it's either:
				// a) an "un-highlight" (so we don't leave mess behind when scrolling)
				// b) currently onscreen
				// Currently this means if you highlight an object then scroll, nodes will scroll
				// into view that should be highlighted but aren't.
				if (settings.hoverway==false || 
				    settings.selectedway==false ||
				    node.within(paint.map.edge_l, paint.map.edge_r, paint.map.edge_t, paint.map.edge_b)) {
				    paint.setHighlight(node,settings); // Triggers redraw if required
				}
				if (settings.selectedway || settings.hoverway)
					nodehighlightsettings=settings;
				else
					nodehighlightsettings={}; 
			}
        }
        
        // An ugly hack to allow nodes that have recently scrolled into view to get highlighted.
        public function updateHighlights():void {
        	if (nodehighlightsettings)
        	   setHighlightOnNodes(nodehighlightsettings);
        }

		// ------------------------------------------------------------------------------------------
		/** Calculate pathlength, patharea, centroid_x, centroid_y, heading[]. 
		* ** this could be made scale-independent - would speed up redraw
		*/
        public function recalculate():void {
            if (suspended) { recalculateDue=true; return; }

            var lx:Number, ly:Number; // last lon; last lat 
            var node:Node, latp:Number, lon:Number; // current node and its location
            var cx:Number=0, cy:Number=0; // cumulative value of centroid
            var way:Way=entity as Way;

            pathlength=0;
            patharea=0;
            if (way.length==0) { return; }

            lx = way.getNode(way.length-1).lon;
            ly = way.getNode(way.length-1).latp;
            for ( var i:uint = 0; i < way.length; i++ ) {
                node = way.getNode(i);
                latp = node.latp;
                lon  = node.lon;
                
                // Calculate way area
                var dlon:Number = lon - lx;
                var dlat:Number = latp - ly;

                // this reworking of the standard centroid calculation formula works better for tiny polygons
                var sc: Number = (lon * dlat - dlon * latp) * paint.map.scalefactor;
                cx += (lx + lon) * sc;
                cy += (ly + latp) * sc;
                patharea += sc;

                // Calculate path length and heading of segments.
                if (i > 0) { 
                    pathlength += Math.sqrt( Math.pow(dlon, 2) + Math.pow(dlat, 2) ); 
                    heading[i-1] = Math.atan2(dlon, dlat); 
                }

                lx=lon; ly=latp;
            }
            heading[way.length-1] = heading[way.length-2];

            pathlength *= paint.map.scalefactor; // length in pixels
            partial = !(way.isArea()) && (pathlength>paint.map.mapwidth*6);

            patharea /= 2;
            if (patharea != 0 && way.isArea()) {
                centroid_x = paint.map.lon2coord(cx / patharea / 6);
                centroid_y = paint.map.latp2coord(cy / patharea / 6);
            } else if (pathlength>0) {
                var c:Array = pointAt(0.5);
                centroid_x = c[0];
                centroid_y = c[1];
            }
            patharea=Math.abs(patharea);
        }
		// ------------------------------------------------------------------------------------------
	
		/** Go through the complex process of drawing this way, including applying styles, casings, fills, fonts... */
		override public function doRedraw():Boolean {
			interactive=false;
			removeSprites();
			if (Way(entity).length==0) { return false; }
			if (!paint.ready) { return false; }

            // Copy tags object, and add states
			var multis:Array=entity.findParentRelationsOfType('multipolygon','outer');
			var tags:Object;
			var isArea:Boolean = Way(entity).isArea();
			if (!entity.hasInterestingTags() && multis.length>0) {
				tags = multis[0].getTagsCopy();
				isArea = true;
			} else {
				tags = entity.getTagsCopy();
			}
            setStateClass('area', isArea);
            setStateClass('background', paint.isBackground);
            setStateClass('tiger', (entity.isUneditedTiger() && Globals.vars.highlightTiger));
            tags=applyStateClasses(tags);
			if (entity.status) { tags['_status']=entity.status; }

			// Keep track of maximum stroke width for hitzone
			var maxwidth:Number=4;

			// Create styleList if not already drawn
			if (!styleList || !styleList.isValidAt(paint.map.scale)) {
				styleList=paint.ruleset.getStyles(entity, tags, paint.map.scale);
			}

			// Which layer?
			layer=styleList.layerOverride();
			if (isNaN(layer)) {
				layer=0;
				if (tags['layer']) { layer=Math.min(Math.max(tags['layer'],paint.minlayer),paint.maxlayer); }
			}

			// Do we have to draw all nodes in the way?
			indexStart=0; indexEnd=Way(entity).length;
			var hasFills:Boolean=styleList.hasFills();
			var i:uint;
			if (hasFills) {
				// draw full line
			} else if (partial) {
				// long polyline (e.g. powerline) so just draw the on-screen section
				var isWithin:Boolean=false;
				for (i=0; i<Way(entity).length-1; i++) {
					if (paint.map.segmentCrosses(Way(entity).getNode(i), Way(entity).getNode(i+1) )) {
						indexStart=Math.max(i-1,0); isWithin=true; break;
					}
				}
				for (i=Way(entity).length-2; i>indexStart; i--) {
					if (paint.map.segmentCrosses(Way(entity).getNode(i), Way(entity).getNode(i+1) )) {
						indexEnd=Math.min(i+2,Way(entity).length); isWithin=true; break;
					}
				}
				if (!isWithin) return true;
			} else if (isNaN(drawOnly)) {
				// draw full line
			} else {
				// we only need to redraw around a dragged vertex
				indexStart=Math.max(0,drawOnly-1);
				indexEnd  =Math.min(drawOnly+2,Way(entity).length);
			}

			// Iterate through each subpart, drawing any styles on that layer
			var drawn:Boolean;
			var inners:Array=[];
			for each (var m:Relation in multis) {
				inners=inners.concat(m.findMembersByRole('inner',Way));
			}

			for each (var subpart:String in styleList.subparts) {
				if (styleList.shapeStyles[subpart]) {
					var s:ShapeStyle=styleList.shapeStyles[subpart];
					var stroke:Shape, fill:Shape, casing:Shape, roadname:Sprite;
					var x0:Number=paint.map.lon2coord(Way(entity).getNode(0).lon);
					var y0:Number=paint.map.latp2coord(Way(entity).getNode(0).latp);
					interactive||=s.interactive;

					// Stroke
					if (s.width)  {
						stroke=new Shape(); addToLayer(stroke,STROKESPRITE,s.sublayer);
						stroke.graphics.moveTo(x0,y0);
						s.applyStrokeStyle(stroke.graphics);
						if (s.dashes && s.dashes.length>0) {
							var segments:Array=dashedLine(stroke.graphics,s.dashes); 
							if (s.line_style) { lineDecoration(stroke.graphics,s,segments); }
						} else { solidLines(stroke.graphics,inners); }
						drawn=true;
						if (s.interactive) { maxwidth=Math.max(maxwidth,s.width); }
					}

					// Fill
					if ((!isNaN(s.fill_color) || s.fill_image) && entity.findParentRelationsOfType('multipolygon','inner').length==0 && isNaN(drawExcept)) {
						fill=new Shape(); addToLayer(fill,FILLSPRITE,s.sublayer);
						fill.graphics.moveTo(x0,y0);
						if (s.fill_image) {
							fill.graphics.beginBitmapFill(FileBank.getInstance().getAsBitmapData(s.fill_image));
						} else {
							s.applyFill(fill.graphics);
						}
						solidLines(fill.graphics,inners);
						fill.graphics.endFill();
						drawn=true;
					}

					// Casing
					if (s.casing_width) { 
						casing=new Shape(); addToLayer(casing,CASINGSPRITE);
						casing.graphics.moveTo(x0,y0);
						s.applyCasingStyle(casing.graphics);
						if (s.casing_dashes && s.casing_dashes.length>0) { dashedLine(casing.graphics,s.casing_dashes); }
																	else { solidLines(casing.graphics,inners); }
						drawn=true;
						if (s.interactive) { maxwidth=Math.max(maxwidth,s.casing_width); }
					}
				}
				
				if (styleList.textStyles[subpart] && isNaN(drawExcept) && !partial) {
					var t:TextStyle=styleList.textStyles[subpart];
					interactive||=t.interactive;
					roadname=new Sprite(); addToLayer(roadname,NAMESPRITE);
					nameformat = t.getTextFormat();
					var a:String=tags[t.text];
					if (a) {
						if (t.font_caps) { a=a.toUpperCase(); }
						if (t.text_center && centroid_x) {
							t.writeNameLabel(roadname,a,centroid_x,centroid_y);
						} else {
							writeNameOnPath(roadname,a,t.text_offset ? t.text_offset : 0);
						}
						if (t.text_halo_radius>0) { roadname.filters=t.getHaloFilter(); }
					}
				}
				
				// ** ShieldStyle to do
			}

			// Draw icons
			var r:Number;
			for (i = indexStart; i < indexEnd; i++) {
                var node:Node = Way(entity).getNode(i);
				var nodeStateClasses:Object={};
//				if (i==0) { nodetags['_heading']= heading[i]; }
//				     else { nodetags['_heading']=(heading[i]+heading[i-1])/2; }
				// ** FIXME - heading isn't currently applied
				nodeStateClasses['junction']=(node.numParentWays>1);
				paint.createNodeUI(node,false,r,layer,nodeStateClasses);
			}
			if (!drawn) { return false; } // If not visible, no hitzone.
			
            // create a generic "way" hitzone sprite
			if (interactive && drawn) {
	            hitzone = new Sprite();
	            hitzone.graphics.lineStyle(maxwidth, 0x000000, 1, false, "normal", CapsStyle.ROUND, JointStyle.ROUND);
	            solidLines(hitzone.graphics,[]);
	            hitzone.visible = false;
				setListenSprite();
			}

			return true;
		}
		
		// ------------------------------------------------------------------------------------------
		// Drawing support functions

		/** Draw solid polyline */
		
		public function solidLines(g:Graphics,inners:Array):void {
			solidLine(g);
			for each (var w:Way in inners) { solidLineOtherWay(g,w); }
		}

		private function solidLine(g:Graphics):void {
			if (indexEnd==0) { return; }
			var way:Way=entity as Way;
			
            var node:Node = way.getNode(indexStart);
 			g.moveTo(paint.map.lon2coord(node.lon), paint.map.latp2coord(node.latp));
			for (var i:uint = indexStart+1; i < indexEnd; i++) {
                node = way.getNode(i);
				if (!isNaN(drawExcept) && (i-1==drawExcept || i==drawExcept)) {
					g.moveTo(paint.map.lon2coord(node.lon), paint.map.latp2coord(node.latp));
				} else {
					g.lineTo(paint.map.lon2coord(node.lon), paint.map.latp2coord(node.latp));
				}
			}
		}

		private function solidLineOtherWay(g:Graphics,way:Way):void {
			if (way.length==0) { return; }
			
			var node:Node = way.getNode(0);
 			g.moveTo(paint.map.lon2coord(node.lon), paint.map.latp2coord(node.latp));
			for (var i:uint = 1; i < way.length; i++) {
				node = way.getNode(i);
				g.lineTo(paint.map.lon2coord(node.lon), paint.map.latp2coord(node.latp));
			}
		}

		/** Draw dashed polyline */
		
		private function dashedLine(g:Graphics,dashes:Array):Array {
			var way:Way=entity as Way;
			var segments:Array=[]; // array of dash locations being constructed for later arrow drawing
			var draw:Boolean=false; // are we drawing or marking empty space till next dash
			var dashleft:Number=0; // how much of current dash is left
			var dc:Array=new Array(); // copy of dashes, gets consumed then replaced
			var xc:Number, yc:Number; // normalised vector coordinates of direction to next node 
			var curx:Number, cury:Number; // current drawing location
			var dx:Number, dy:Number, segleft:Number=0; // distance remaining until next node
 			var i:int=indexStart; // node index
 			var dashstartx:int, dashstarty:int; // needed to draw reverse arrows
 			var dashstartxc: Number, dashstartyc: Number;

            var node:Node = way.getNode(i);
            var nextNode:Node = way.getNode(i);
 			g.moveTo(paint.map.lon2coord(node.lon), paint.map.latp2coord(node.latp));
			while (i < indexEnd-1 || segleft>0) {
				if (dashleft<=0) {	// should be ==0
				    // finished drawing current dash, pop another one off the pattern, looping if necessary
					if (dc.length==0) { dc=dashes.slice(0); }
					dashleft=dc.shift();
					if (draw) { segments.push([curx,cury,xc,yc, dashstartx, dashstarty, dashstartxc, dashstartyc]); }
					draw=!draw;
					// record start of each dash, if we need to draw a reverse arrow head later
					dashstartx = curx; dashstarty = cury;
					dashstartxc = xc; dashstartyc = yc;
				}
				if (i==drawExcept || i==drawExcept+1) { draw=false; }
				if (segleft<=0) {	// should be ==0
                    // arrived at target node. calculate direction to next node.
                    node = way.getNode(i);
                    nextNode = way.getNode(i+1);
					curx=paint.map.lon2coord(node.lon);
                    dx=paint.map.lon2coord(nextNode.lon)-curx;
					cury=paint.map.latp2coord(node.latp);
                    dy=paint.map.latp2coord(nextNode.latp)-cury;
					segleft=Math.sqrt(dx*dx+dy*dy);
					xc = dx/segleft;
					yc = dy/segleft;
					if (i==0) {
                        // record start location of very first dash
                        dashstartx = curx; dashstarty = cury;
                        dashstartxc = xc; dashstartyc = yc;
					}
					i++;
				}

				if (segleft<=dashleft) {
					// the path segment is shorter than the dash: draw to end of segment
		 			curx+=dx; cury+=dy;
					moveLine(g,curx,cury,draw);
					dashleft-=segleft; segleft=0;
				} else {
					// draw whole dash, then loop
					curx+=dashleft*xc; dx-=dashleft*xc;
					cury+=dashleft*yc; dy-=dashleft*yc;
					moveLine(g,curx,cury,draw);
					segleft-=dashleft; dashleft=0;
				}
			}
			return segments;
		}

		private function moveLine(g:Graphics,x:Number,y:Number,draw:Boolean):void {
			if (draw) { g.lineTo(x,y); }
				 else { g.moveTo(x,y); }
		}

		/** Draw decoration (arrows etc.) */
		
		private function lineDecoration(g:Graphics,s:ShapeStyle,segments:Array):void {
			var c:int=s.color ? s.color : 0;
			switch (s.line_style.toLowerCase()) {

				case 'arrows':; case 'arrows-reversed':
					var w:Number=s.width*1.5;  // width of arrow
					var l:Number=s.width*2;	   // length of arrow
					g.lineStyle(1,c);
					for each (var seg:Array in segments) {
						g.beginFill(c);
						// seg: {dashendx, dashendy, dx, dy, dashstartx, dashstarty, dashstartdx, dashstartdy} 
						// where dx is normalised x component of direction vector
						// note that a dash can go around a corner, so the info is not redundant
						
						if (s.line_style.toLowerCase() == "arrows-reversed") {
	                        g.moveTo(seg[4]-l*seg[6], seg[5]-l*seg[7]); // note reversed arrow head
	                        g.lineTo(seg[4]-w*seg[7], seg[5]+w*seg[6]);
	                        g.lineTo(seg[4]+w*seg[7], seg[5]-w*seg[6]);
						} else {
							g.moveTo(seg[0]+l*seg[2], seg[1]+l*seg[3]);
	                        g.lineTo(seg[0]-w*seg[3], seg[1]+w*seg[2]);
	                        g.lineTo(seg[0]+w*seg[3], seg[1]-w*seg[2]);
	                    }
						g.endFill();
					}
					break;
                case 'triangle':
                    w=s.width*10;   //triangle egde
                    g.lineStyle(1,c);
                    for each (seg in segments) {
                        g.beginFill(c);
                        var angle0:Number = -Math.atan2(seg[3], seg[2]) + Math.PI / 2; //0
                        var angle1:Number = -Math.atan2(seg[3], seg[2]) - Math.PI/6;       //60
                        g.moveTo(seg[0], seg[1]);//start 0,0
                        g.lineTo(seg[0] - w * Math.sin(angle0), seg[1] - w * Math.cos(angle0));
                        g.lineTo(seg[0] + w * Math.sin(angle1), seg[1] + w * Math.cos(angle1));
                        g.endFill();
                    }
                    break;
				}
		}
		
		/** Find point partway (0-1) along a path
		  * @return (x,y,angle)
		  * inspired by senocular's Path.as */
		
		private function pointAt(t:Number):Array {
			var way:Way=entity as Way;
			var totallen:Number = t*pathlength;
			var curlen:Number = 0;
			var dx:Number, dy:Number, seglen:Number;
			for (var i:int = 1; i < way.length; i++){
				dx=paint.map.lon2coord(way.getNode(i).lon)-paint.map.lon2coord(way.getNode(i-1).lon);
				dy=paint.map.latp2coord(way.getNode(i).latp)-paint.map.latp2coord(way.getNode(i-1).latp);
				seglen=Math.sqrt(dx*dx+dy*dy);
				if (totallen > curlen+seglen) { curlen+=seglen; continue; }
				return new Array(paint.map.lon2coord(way.getNode(i-1).lon)+(totallen-curlen)/seglen*dx,
								 paint.map.latp2coord(way.getNode(i-1).latp)+(totallen-curlen)/seglen*dy,
								 Math.atan2(dy,dx));
			}
			return new Array(0, 0, 0);
		}

		/** Draw name along path
		 * based on code by Tom Carden
		 * */
		
		private function writeNameOnPath(s:Sprite,a:String,textOffset:Number=0):void {
			if (a.length*Number(nameformat.size || 12)*0.6 > pathlength) return; // don't bother measuring text if clearly too long

			// make a dummy textfield so we can measure its width
			var tf:TextField = new TextField();
			tf.defaultTextFormat = nameformat;
			tf.text = a;
			tf.width = tf.textWidth+4;
			tf.height = tf.textHeight+4;
			if (pathlength<tf.width) { return; }	// no room for text?

			var t1:Number = (pathlength/2 - tf.width/2) / pathlength; var p1:Array=pointAt(t1);
			var t2:Number = (pathlength/2 + tf.width/2) / pathlength; var p2:Array=pointAt(t2);
			var mult:Number = (Capabilities.playerType == "Desktop") ? Number(nameformat.size)*1.8 : 1;

			var angleOffset:Number; // so we can do a 180º if we're running backwards
			var offsetSign:Number;  // -1 if we're starting at t2
			var tStart:Number;      // t1 or t2

			// make sure text doesn't run right->left or upside down
			if (p1[0] < p2[0] && 
				p1[2] < Math.PI/2 &&
				p1[2] > -Math.PI/2) {
				angleOffset = 0; offsetSign = 1; tStart = t1;
			} else {
				angleOffset = Math.PI; offsetSign = -1; tStart = t2;
			} 

			// make a textfield for each char, centered on the line,
			// using getCharBoundaries to rotate it around its center point
			var chars:Array = a.split('');
			for (var i:int = 0; i < chars.length; i++) {
				var rect:Rectangle = tf.getCharBoundaries(i);
				if (rect) {
					s.addChild(rotatedLetter(chars[i],
						 					 tStart + offsetSign*(rect.left*mult + rect.width*mult/2)/pathlength,
											 rect.width*mult, tf.height, angleOffset, textOffset));
				}
			}
		}

		private function rotatedLetter(char:String, t:Number, w:Number, h:Number, a:Number, o:Number):TextField {
			var tf:TextField = new TextField();
            tf.mouseEnabled = false;
            tf.mouseWheelEnabled = false;
			tf.defaultTextFormat = nameformat;
			tf.embedFonts = true;
			tf.text = char;
			tf.width = tf.textWidth+4;
			tf.height = tf.textHeight+4;

			var p:Array=pointAt(t);
			var matrix:Matrix = new Matrix();
			matrix.translate(-w/2, -h/2-o);
			// ** add (say) -4 to the height to move it up by 4px
			matrix.rotate(p[2]+a);
			matrix.translate(p[0], p[1]);
			tf.transform.matrix = matrix;
			return tf;
		}
		
		public function getNodeAt(x:Number, y:Number):Node {
			var way:Way=entity as Way;
			for (var i:uint = 0; i < way.length; i++) {
                var node:Node = way.getNode(i);
                var nodeX:Number = paint.map.lon2coord(node.lon);
                var nodeY:Number = paint.map.latp2coord(node.latp);
                if ( nodeX >= x-NODESIZE && nodeX <= x+NODESIZE &&
                     nodeY >= y-NODESIZE && nodeY <= y+NODESIZE )
                    return node;
            }
            return null;
		}

		// ------------------------------------------------------------------------------------------
		/* Interaction */
        // TODO: can this be sped up? Hit testing for long ways (that go off the screen) seems to be very slow. */
		public function hitTest(x:Number, y:Number):Way {
			if (hitzone && hitzone.hitTestPoint(x,y,true)) { return entity as Way; }
			return null;
		}
	}
}
