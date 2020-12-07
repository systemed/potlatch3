package net.systemeD.halcyon {

	/** A class permitting you to load XML files containing 'include' elements (for example,
	*   <include file="cuisine.xml" />, which will be automatically replaced with the contents of the file.
	*
	*   Typical usage:
	*
	*		xmlLoader=new NestedXMLLoader();
	*		xmlLoader.addEventListener(Event.COMPLETE, onFeatureLoad);
	*		xmlLoader.load("root.xml");
	*
	*	onFeatureLoad can then access the XML via event.target.xml.
	*/

    import net.systemeD.P3;
	import flash.events.*;

	public class NestedXMLLoader extends EventDispatcher {
		public var xml:XML = null;
		private var count:int;

		public function NestedXMLLoader() {
		}
		
		public function load(url:String):void {
			P3.fetch(url, function(data:String, success:Boolean, err:String):void {
	            count=1;
				xml = new XML(data);
				for each (var inc:XML in xml.descendants('include')) {
					count++;
					replaceXML(inc);
				}
	            decreaseCount();
			});
		}

		private function replaceXML(inc:XML):void {
			var xmlLoader:NestedXMLLoader=new NestedXMLLoader();
			var includeElement:XML=inc;
			xmlLoader.addEventListener(Event.COMPLETE, function(event:Event):void {
				includeElement.parent().replace(findChildIndex(includeElement),event.target.xml);
				decreaseCount();
			});
			xmlLoader.load(inc.@file);
		}

		private function findChildIndex(child:XML):int {
			var i:uint=0;
			for each (var sibling:XML in child.parent().children()) {
				if (sibling==child) return i;
				i++;
			}
			return -1;
		}
		
		private function decreaseCount():void {
			count--; if (count>0) return;
			fireComplete();
		}
		
		private function fireComplete():void {
			var event:Event=new Event(Event.COMPLETE);
			dispatchEvent(event);
		}
	}
}
