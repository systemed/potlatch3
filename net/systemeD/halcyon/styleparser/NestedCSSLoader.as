package net.systemeD.halcyon.styleparser {

	import net.systemeD.P3;
    import flash.events.*;

	/** A class permitting you to load CSS files containing 'import' rules, which will be 
		automatically replaced with the contents of the file.									<p>
	
	   	Typical usage:																			</p><pre>
	
			cssLoader=new NestedCSSLoader();
			cssLoader.addEventListener(Event.COMPLETE, doParseCSS);
			cssLoader.load("potlatch.css");														</pre><p>
	
		doParseCSS can then access the CSS via event.target.css.								</p>
	*/

	public class NestedCSSLoader extends EventDispatcher {
		public var css:String;
		private var count:int;

		private static const IMPORT:RegExp=/@import\s*[^'"]*['"]([^'"]+)['"][^;]*;/g;		// '

		public function NestedCSSLoader() {
		}
		
		public function load(url:String):void {
			P3.fetch(url, function(data:String, success:Boolean, err:String):void {
				if (!success) { trace("error loading css"); return; }
				fileLoaded(data);
			});
		}
		
		private function fileLoaded(str:String):void {
			css = str.slice();
			count = 1;

			var results:Array = str.match(IMPORT);
            while (results.length > 0) {
                IMPORT.lastIndex = 0;
                var result:Object = IMPORT.exec(results.shift());
				count++;
				replaceCSS(result[1],result[0]);
			}
            decreaseCount();
		}

		private function replaceCSS(filename:String, toReplace:String):void {
			var cssLoader:NestedCSSLoader=new NestedCSSLoader();
			var replaceText:String=toReplace;
			cssLoader.addEventListener(Event.COMPLETE, function(event:Event):void {
				css=css.replace(replaceText,event.target.css);
				decreaseCount();
			});
			cssLoader.load(filename);
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
