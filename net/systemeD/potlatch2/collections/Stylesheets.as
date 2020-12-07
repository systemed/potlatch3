package net.systemeD.potlatch2.collections {

	import flash.events.EventDispatcher;
	import flash.events.Event;
	import flash.net.*;
	import net.systemeD.halcyon.Map;
	import net.systemeD.halcyon.Stylesheet;
	import net.systemeD.potlatch2.FunctionKeyManager;
	import net.systemeD.P3;
	import mx.collections.ArrayCollection;

    /**
    *  A collection of available stylesheets
    */
	public class Stylesheets extends EventDispatcher {

        private static const GLOBAL_INSTANCE:Stylesheets = new Stylesheets();
        public static function instance():Stylesheets { return GLOBAL_INSTANCE; }

		private static const DEFAULT:String = 'stylesheets/potlatch.css';

		private var collection:Vector.<Stylesheet> = new Vector.<Stylesheet>;
		private var _selected:Stylesheet;

		/* Load catalogue file */

		public function init():void {
			_selected = new Stylesheet("Default", 
				SharedObject.getLocal("user_state","/").data['stylesheet_url'] || DEFAULT);
			
			P3.fetch("stylesheets.xml", function(data:String, success:Boolean, err:String):void {
				if (!success) return;
				var xml:XML = new XML(data);
				var saved_url:String = SharedObject.getLocal("user_state","/").data['stylesheet_url'];
				var saved_name:String= SharedObject.getLocal("user_state","/").data['stylesheet_name'];
				var isInMenu:Boolean=false, isSet:Boolean=false;

	            // first, build the menu from the stylesheet list.
	            // Also ensure the saved_url is in the menu (might be either saved from before, or supplied via loaderInfo)
	            collection = new Vector.<Stylesheet>;
				for each(var set:XML in xml.stylesheet) {
	                var corestyle:Boolean = true;
	                if (set.corestyle == "no" || set.corestyle == "false") { corestyle = false }

	                var s:Stylesheet = new Stylesheet(set.name, set.url, corestyle);
	                collection.push(s);
					if (s.url==saved_url) { isInMenu=true; }
					else if (s.name==saved_name && s.name!='Custom') { isInMenu=true; saved_url=s.url; }
				}
				if (saved_url && !isInMenu) { collection.push(new Stylesheet(saved_name, saved_url)); }

	            // pick a stylesheet to be set. It should be the saved one, if it is in the menu
	            // or alternatively the first one on the menu,
	            // or finally try 'stylesheets/potlatch.css'
				for each (var ss:Stylesheet in collection) {
					if (ss.name==saved_name || ss.url==saved_url) {
						setStylesheet(ss);
	                    isSet = true;
	                    break;
					}
				}
	            if (!isSet) {
	              if(collection.length > 0) {
	                setStylesheet(collection[0]);
	              } else {
	                //hit and hope. FIXME should this be an error state?
	                var d:Stylesheet = new Stylesheet('Potlatch', DEFAULT);
	                collection.push(d);
	                setStylesheet(d);
	              }
	            }
				FunctionKeyManager.instance().registerListener('Map style',
					function(o:String):void { setStylesheet(findStylesheetWithName(o)); });
				dispatchEvent(new Event("collection_changed"));
			});
		}

		public function setStylesheet(ss:Stylesheet):void {
			_selected=ss;
			dispatchEvent(new CollectionEvent(CollectionEvent.SELECT, ss.url));
			var obj:SharedObject = SharedObject.getLocal("user_state","/");
			obj.setProperty("stylesheet_url",ss.url);
			obj.setProperty("stylesheet_name",ss.name);
			try { obj.flush(); } catch (e:Error) {}
		}

		/** The currently selected stylesheet */
		public function get selected():Stylesheet { return _selected; }

		private function findStylesheetWithName(name:String):Stylesheet {
			for each (var ss:Stylesheet in collection) {
				if (ss.name==name) { return ss; }
			}
			return null;
		}

		/**
		*  Get the list of core stylesheets
		*/
		[Bindable(event="collection_changed")]
		public function getCollection():ArrayCollection {
			var available:Array=[];
			for each (var ss:Stylesheet in collection) {
                if (ss.coreStyle == true) {
                  available.push(ss);
                }
			}
			return new ArrayCollection(available);
		}

		/**
		*  Get the list of all stylesheets
		*/
		[Bindable(event="collection_changed")]
		public function getFullCollection():ArrayCollection {
            var all:Array=[];
            for each (var ss:Stylesheet in collection) {
                all.push(ss);
            }
            return new ArrayCollection(all);
        }
	}
}
