package net.systemeD.halcyon {

	import flash.display.Loader;
	import flash.display.Sprite;
	import flash.events.*;
	import flash.external.ExternalInterface;
	import flash.geom.Rectangle;
	import flash.net.*;
	import flash.text.Font;
	import flash.text.TextField;
	import flash.ui.Keyboard;
	
	import net.systemeD.halcyon.connection.*;
	import net.systemeD.halcyon.styleparser.*;

//	for experimental export function:
//	import flash.net.FileReference;
//	import com.adobe.images.JPGEncoder;

    /** The representation of part of the map on the screen, including information about coordinates, background imagery, paint properties etc. */
    public class Map extends Sprite {

		/** master map scale - how many Flash pixels in 1 degree longitude (for Landsat, 5120) */
		public const MASTERSCALE:Number=5825.4222222222; 
												
		/** don't zoom out past this */
		public const MINSCALE_TILES:uint=2;
		public const MINSCALE_DATA:uint=15;
		/** don't zoom in past this */
		public const MAXSCALE:uint=23; 

		// Container for MapPaint objects
		private var paintContainer:Sprite;

		/** map scale */
		public var scale:uint=14;						 
		/** current scaling factor for lon/latp */
		public var scalefactor:Number;

		public var edge_l:Number;						// current bounding box
		public var edge_r:Number;						//  |
		public var edge_t:Number;						//  |
		public var edge_b:Number;						//  |
		public var centre_lat:Number;					// centre lat/lon
		public var centre_lon:Number;					//  |

		/** urllon-xradius/masterscale; */ 
		public var baselon:Number;
		/** lat2lat2p(urllat)+yradius/masterscale; */
		public var basey:Number; 
		/** width (Flash pixels) */
		public var mapwidth:uint; 
		/** height (Flash pixels) */
		public var mapheight:uint; 

		/** Is the map being panned */
		public var dragstate:uint=NOT_DRAGGING;			// dragging map (panning)
		/** Can the map be panned */
		private var _draggable:Boolean=true;			//  |
		private var lastxmouse:Number;					//  |
		private var lastymouse:Number;					//  |
		private var downX:Number;						//  |
		private var downY:Number;						//  |
		private var downTime:Number;					//  |
		public const NOT_DRAGGING:uint=0;				//  |
		public const NOT_MOVED:uint=1;					//  |
		public const DRAGGING:uint=2;					//  |
		public const SWALLOW_MOUSEUP:uint=3;			//  |
		/** How far the map can be dragged without actually triggering a pan. */
		public const TOLERANCE:uint=7;					//  |
		
		/** object containing HTML page parameters: lat, lon, zoom, background_dim, background_sharpen, tileblocks */
		public var initparams:Object; 

		/** reference to backdrop sprite */
		public var backdrop:Object; 
		/** background tile object */
		public var tileset:TileSet; 
		/** show all objects, even if unstyled? */
		public var showall:Boolean=true; 
		
		// ------------------------------------------------------------------------------------------
		/** Map constructor function */
        public function Map(overlay:Sprite) {
			// Remove any existing sprites
			while (numChildren) { removeChildAt(0); }

			// Tile background
			setScaleFactor(scale);
			tileset=new TileSet(this,overlay);
			addChild(tileset);

			// Container for all MapPaint objects
			paintContainer = new Sprite();
			addChild(paintContainer);

			addEventListener(Event.ENTER_FRAME, everyFrame);
			scrollRect=new Rectangle(0,0,800,600);
		}

		// ------------------------------------------------------------------------------------------
		/** Initialise map at a given lat/lon */
        public function init(startlat:Number, startlon:Number, startscale:uint=0):void {
			setScaleFactor(startscale);
			setBase(startlat,startlon,true);
			if (startscale>0) {
				scale=startscale;
				this.dispatchEvent(new MapEvent(MapEvent.SCALE, {scale:scale}));
			}
			updateCoords(0,0);
            this.dispatchEvent(new Event(MapEvent.INITIALISED));
			download();
        }

		// ------------------------------------------------------------------------------------------
		/** Recalculate co-ordinates from new Flash origin */

		private function updateCoords(tx:Number,ty:Number):void {
			setScrollRectXY(tx,ty);

			edge_t=coord2lat(-ty          );
			edge_b=coord2lat(-ty+mapheight);
			edge_l=coord2lon(-tx          );
			edge_r=coord2lon(-tx+mapwidth );
			setCentre();

			tileset.update();
		}
		
		/** Move the map to centre on a given latitude/longitude. */
		public function updateCoordsFromLatLon(lat:Number,lon:Number):void {
			var cy:Number=-(lat2coord(lat)-mapheight/2);
			var cx:Number=-(lon2coord(lon)-mapwidth/2);
			updateCoords(cx,cy);
		}
		
		private function setScrollRectXY(tx:Number,ty:Number):void {
			var w:Number=scrollRect.width;
			var h:Number=scrollRect.height;
			scrollRect=new Rectangle(-tx,-ty,w,h);
		}
		private function setScrollRectSize(width:Number,height:Number):void {
			var sx:Number=scrollRect.x ? scrollRect.x : 0;
			var sy:Number=scrollRect.y ? scrollRect.y : 0;
			scrollRect=new Rectangle(sx,sy,width,height);
		}
		
		private function getX():Number { return -scrollRect.x; }
		private function getY():Number { return -scrollRect.y; }
		
		private function setCentre():void {
			centre_lat=coord2lat(-getY()+mapheight/2);
			centre_lon=coord2lon(-getX()+mapwidth/2);
			this.dispatchEvent(new MapEvent(MapEvent.MOVE, {lat:centre_lat, lon:centre_lon, scale:scale, minlon:edge_l, maxlon:edge_r, minlat:edge_b, maxlat:edge_t}));
		}
		
		/** Sets the offset between the background imagery and the map. */
		public function nudgeBackground(x:Number,y:Number):void {
			this.dispatchEvent(new MapEvent(MapEvent.NUDGE_BACKGROUND, { x: x, y: y }));
		}

		private function moveMap(dx:Number,dy:Number):void {
			updateCoords(getX()+dx,getY()+dy);
			updateAllEntityUIs(false, false);
			download();
		}
		
		/** Recentre map at given lat/lon, updating the UI and downloading entities. */
		public function moveMapFromLatLon(lat:Number, lon:Number, resetBase:Boolean=false):void {
			if (resetBase && setBase(lat,lon)) tileset.reposition();
			updateCoordsFromLatLon(lat,lon);
			updateAllEntityUIs(false,false);
			download();
		}

		public function moveMapFromLatLonDefaultScale(lat:Number,lon:Number):void {
            moveMapFromLatLonScale( lat, lon, scale<MINSCALE_DATA ? 17 : scale );
		}

		public function moveMapFromLatLonScale(lat:Number,lon:Number,z:Number):void {
			setScaleFactor(z);
			var bigJump:Boolean = setBase(lat,lon);
			if (bigJump) tileset.reposition();
			setScale(z);
			updateCoordsFromLatLon(lat,lon);
			tileset.changeScale(z);
			updateAllEntityUIs(true,true);
			download();
			this.dispatchEvent(new MapEvent(MapEvent.JUMP, { y:lat, x:lon, big: bigJump }));
		}
		
		/** Recentre map at given lat/lon, if that point is currently outside the visible area. */
		public function scrollIfNeeded(lat:Number,lon:Number): void{
            if (lat> edge_t || lat < edge_b || lon < edge_l || lon > edge_r) {
                moveMapFromLatLon(lat, lon, false);
            }
		}

		// Convert between lat/lon (map coords) and screen coords
		public function latp2coord(a:Number):Number	{ return -(a-basey)*scalefactor; }
		public function coord2latp(a:Number):Number	{ return a/-scalefactor+basey; }
		public function lon2coord(a:Number):Number	{ return (a-baselon)*scalefactor; }
		public function coord2lon(a:Number):Number	{ return a/scalefactor+baselon; }

		// Convert between straight latitudes and projected latitudes 
		public function latp2lat(a:Number):Number	{ return 180/Math.PI * (2 * Math.atan(Math.exp(a*Math.PI/180)) - Math.PI/2); }
		public function lat2latp(a:Number):Number	{ return 180/Math.PI * Math.log(Math.tan(Math.PI/4+a*(Math.PI/180)/2)); }

		public function lat2coord(a:Number):Number	{ return -(lat2latp(a)-basey)*scalefactor; }
		public function coord2lat(a:Number):Number	{ return latp2lat(a/-scalefactor+basey); }

		// Scale factor doubles with each zoom level (z13=MASTERSCALE, z14=2*MASTERSCALE, etc.)
		private function setScaleFactor(z:Number):void { 
			scalefactor=MASTERSCALE*Math.pow(2,z-13);
		}
		// Adjust baselon/baselat if it's more than 2° different from current
		private function setBase(lat:Number,lon:Number,force:Boolean=false):Boolean {
			var newbl:Number = lon          -(mapwidth /2)/scalefactor;
			var newby:Number = lat2latp(lat)+(mapheight/2)/scalefactor;
			if (force || Math.abs(newbl-baselon)>1 || Math.abs(newby-basey)>1) {
				baselon=newbl; basey=newby; return true;
			}
			return false;
		}

		// Does a segment cross the map?
		public function segmentCrosses(n0:Node,n1:Node):Boolean {
			var xmin:Number = Math.min(n0.lon,n1.lon),
				ymin:Number = Math.min(n0.lat,n1.lat),
				xmax:Number = Math.max(n0.lon,n1.lon),
				ymax:Number = Math.max(n0.lat,n1.lat);
			return ( (xmin>=edge_l && xmin<=edge_r) ||
					 (xmax>=edge_l && xmax<=edge_r) ||
					 (xmin< edge_l && xmax> edge_r) ) &&
				   ( (ymin>=edge_b && ymin<=edge_t) ||
					 (ymax>=edge_b && ymax<=edge_t) ||
					 (ymin< edge_b && ymax> edge_t) );
		}

		// ------------------------------------------------------------------------------------------
		/** Resize map size based on current stage and height */

		public function updateSize(w:uint, h:uint):void {
			mapwidth = w; centre_lon=coord2lon(-getX()+w/2);
			mapheight= h; centre_lat=coord2lat(-getY()+h/2);
			setScrollRectSize(w,h);
			updateCoords(getX(),getY());

			this.dispatchEvent(new MapEvent(MapEvent.RESIZE, {width:w, height:h}));
			this.dispatchEvent(new MapEvent(MapEvent.MOVE_END, {lat:centre_lat, lon:centre_lon, scale:scale, minlon:edge_l, maxlon:edge_r, minlat:edge_b, maxlat:edge_t}));
			
            if ( backdrop != null ) {
                backdrop.width=mapwidth;
                backdrop.height=mapheight;
            }
            if ( mask != null ) {
                mask.width=mapwidth;
                mask.height=mapheight;
            }
		}

        /** Download map data. Data is downloaded for the currently visible layers
        * The bounding box for the download is taken from the current map edges.
        */
		public function download():void {
			if (scale<MINSCALE_DATA) return;	// could potentially be different per layer
			for (var i:uint=0; i<paintContainer.numChildren; i++)
				if(getLayerAt(i).visible == true) {
                    getLayerAt(i).connection.loadBbox(edge_l,edge_r,edge_t,edge_b);
                }
		}

		/** Is the map editable? */
		public function get isEditable():Boolean { return scale>=MINSCALE_DATA; }

        // Handle mouse events on ways/nodes
        private var mapController:MapController = null;

        /** Assign map controller. */
        public function setController(controller:MapController):void {
            this.mapController = controller;
        }

        public function entityMouseEvent(event:MouseEvent, entity:Entity):void {
            if ( mapController != null )
                mapController.entityMouseEvent(event, entity);
        }

		// ------------------------------------------------------------------------------------------
		// Add layers
		
		public function addLayer(connection:Connection, styleurl:String, backgroundlayer:Boolean=true, interactive:Boolean=false):MapPaint {
			var paint:MapPaint=new MapPaint(this, connection, styleurl, -5, 5);
			paintContainer.addChildAt(paint,0);
			paint.isBackground=backgroundlayer;
			paint.interactive=interactive;
			return paint;
		}

		public function removeLayerByName(name:String):void {
			for (var i:uint=0; i<paintContainer.numChildren; i++) {
				if (getLayerAt(i).connection.name==name)
					paintContainer.removeChildAt(i);
					// >>>> REFACTOR: needs to do the equivalent of VectorLayer.blank()
			}
		}
		
		public function findLayer(name:String):MapPaint {
			for (var i:uint=0; i<paintContainer.numChildren; i++)
				if (getLayerAt(i).connection.name==name) return getLayerAt(i);
			return null;
		}

		private function getLayerAt(i:uint):MapPaint {
			return MapPaint(paintContainer.getChildAt(i));
		}

        /** Get all the layers available for this Map object
        *   @return An array of MapPaint objects */
        public function getLayers():Array {
            var a:Array = [];
            for (var i:uint=0; i<paintContainer.numChildren; i++) {
                a.push(getLayerAt(i));
            }
            return a;
        }
		
		/* Find which layer is editable */
		public function get editableLayer():MapPaint {
			var editableLayer:MapPaint;
			for (var i:uint=0; i<paintContainer.numChildren; i++) {
				if (!getLayerAt(i).isBackground) {
					if (editableLayer) trace("Multiple editable layers found");
					editableLayer=getLayerAt(i);
				}
			}
			return editableLayer;
		}

		/** Find which paint object an entity will be displayed on. */
		public function getLayerForEntity(entity:Entity):MapPaint {
			for (var i:uint=0; i<paintContainer.numChildren; i++) {
				if (getLayerAt(i).sameConnection(entity)) return getLayerAt(i);
			}
			return null;
		}

		// ------------------------------------------------------------------------------------------
		// Redraw all items, zoom in and out
		
		public function updateAllEntityUIs(redraw:Boolean,remove:Boolean):void {
			for (var i:uint=0; i<paintContainer.numChildren; i++)
				getLayerAt(i).updateEntityUIs(redraw, remove);
		}
		public function redraw():void {
			for (var i:uint=0; i<paintContainer.numChildren; i++)
				getLayerAt(i).redraw();
		}
		public function redrawPOIs():void { 
			for (var i:uint=0; i<paintContainer.numChildren; i++)
				getLayerAt(i).redrawPOIs();
		}
		
		public function zoomIn(increment:uint=1, toLat:Number=NaN, toLon:Number=NaN):void {
			changeScale(Math.min(scale+increment, MAXSCALE), toLat, toLon);
		}
		
		public function zoomOut(increment:uint=1, toLat:Number=NaN, toLon:Number=NaN):void {
			changeScale(Math.max(scale-increment, MINSCALE_TILES), toLat, toLon);
		}
		
		public function setScale(newscale:uint):void {
			scale=newscale;
			this.dispatchEvent(new MapEvent(MapEvent.SCALE, {scale:scale}));
			setScaleFactor(scale);
		}

		public function changeScale(newscale:uint,toLat:Number=NaN,toLon:Number=NaN):void {
			setScale(newscale);
			var lat:Number = isNaN(toLat) ? (edge_t+edge_b)/2 : toLat;
			var lon:Number = isNaN(toLon) ? (edge_l+edge_r)/2 : toLon;
			if (setBase(lat,lon)) { tileset.empty(); }
			updateCoordsFromLatLon(lat,lon);	// recentre
			tileset.changeScale(scale);
			updateAllEntityUIs(true,true);
			download();
		}

		/** Set background dimming on/off. */
		public function setDimming(dim:Boolean):void {
			if (tileset) { tileset.setDimming(dim); }
		}
		
		/** Return background dimming. */
		public function getDimming():Boolean {
			if (tileset) { return tileset.getDimming(); }
			return true;
		}

		/** Set background sharpening on/off. */
		public function setSharpen(sharpen:Boolean):void {
			if (tileset) { tileset.setSharpen(sharpen); }
		}
		/** Return background sharpening. */
		public function getSharpen():Boolean {
			if (tileset) { return tileset.getSharpen(); }
			return false;
		}

		// ------------------------------------------------------------------------------------------
		// Export (experimental)
		// ** just a bit of fun for now!
		// really needs to take a bbox, and make sure that the image is correctly cropped/resized 
		// to that area (will probably require creating a new DisplayObject with a different origin
		// and mask)
/*		
		public function export():void {
			trace("size is "+this.width+","+this.height);
			var jpgSource:BitmapData = new BitmapData(800,800); // (this.width, this.height);
			jpgSource.draw(this);
			var jpgEncoder:JPGEncoder = new JPGEncoder(85);
			var jpgStream:ByteArray = jpgEncoder.encode(jpgSource);
			var fileRef:FileReference = new FileReference();
//			fileRef.save(jpgStream,'map.jpeg');
		}

*/

		// ==========================================================================================
		// Events
		
		// ------------------------------------------------------------------------------------------
		// Mouse events
		
		/** Should map be allowed to pan? */
		public function set draggable(draggable:Boolean):void {
			_draggable=draggable;
			dragstate=NOT_DRAGGING;
		}

		/** Prepare for being dragged by recording start time and location of mouse. */
		public function mouseDownHandler(event:MouseEvent):void {
			if (!_draggable) { return; }
			if (dragstate==DRAGGING) { moveMap(x,y); dragstate=SWALLOW_MOUSEUP; }	// cancel drag if mouse-up occurred outside the window (thanks, Safari)
			else { dragstate=NOT_MOVED; }
			lastxmouse=stage.mouseX; downX=stage.mouseX;
			lastymouse=stage.mouseY; downY=stage.mouseY;
			downTime=new Date().getTime();
		}
        
		/** Respond to mouse up by possibly moving map. */
		public function mouseUpHandler(event:MouseEvent=null):void {
			if (dragstate==DRAGGING) { moveMap(x,y); }
			dragstate=NOT_DRAGGING;
		}
        
		/** Respond to mouse movement, dragging the map if tolerance threshold met. */
		public function mouseMoveHandler(event:MouseEvent):void {
			if (!_draggable) { return; }
			if (dragstate==NOT_DRAGGING) { 
			   this.dispatchEvent(new MapEvent(MapEvent.MOUSE_MOVE, { x: coord2lon(mouseX), y: coord2lat(mouseY) }));
               return; 
            }
			
			if (dragstate==NOT_MOVED) {
				if (new Date().getTime()-downTime<300) {
					if (Math.abs(downX-stage.mouseX)<=TOLERANCE   && Math.abs(downY-stage.mouseY)<=TOLERANCE  ) return;
				} else {
					if (Math.abs(downX-stage.mouseX)<=TOLERANCE/2 && Math.abs(downY-stage.mouseY)<=TOLERANCE/2) return;
				}
				dragstate=DRAGGING;
			}
			
			setScrollRectXY(getX()+stage.mouseX-lastxmouse,getY()+stage.mouseY-lastymouse);
			lastxmouse=stage.mouseX; lastymouse=stage.mouseY;
			setCentre();
		}
        
		// ------------------------------------------------------------------------------------------
		// Do every frame

		private function everyFrame(event:Event):void {
			if (stage.focus && !stage.contains(stage.focus)) { stage.focus=stage; }
		}

		// ------------------------------------------------------------------------------------------
		// Miscellaneous events
		
		/** Respond to cursor movements and zoom in/out.*/
		public function keyUpHandler(event:KeyboardEvent):void {
			if (event.target is TextField) return;				// not meant for us
			switch (event.keyCode) {
				case Keyboard.PAGE_UP:	zoomIn(); break;                 // Page Up - zoom in
				case Keyboard.PAGE_DOWN:	zoomOut(); break;            // Page Down - zoom out
				case Keyboard.LEFT:	moveMap(mapwidth/2,0); break;        // left cursor
				case Keyboard.UP:	moveMap(0,mapheight/2); break;		 // up cursor
				case Keyboard.RIGHT:	moveMap(-mapwidth/2,0); break;   // right cursor
				case Keyboard.DOWN:	moveMap(0,-mapheight/2); break;      // down cursor
			}
		}

	}
}
