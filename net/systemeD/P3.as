package net.systemeD {

	import flash.net.*;
    import flash.events.*;
	import mx.core.FlexGlobals;
    import net.systemeD.halcyon.AttentionEvent;
    import com.adobe.serialization.json.JSON;
	import flash.system.ApplicationDomain;

	// General utility class

	public class P3 {

		// Dispatch one-time event
		
		public static function addOneTimeEventListener(dispatcher:IEventDispatcher,eventType:String,listener:Function):void {
			var f:Function = function(e:Event):void {
				dispatcher.removeEventListener(eventType,f);
				listener(e);
			}
			dispatcher.addEventListener(eventType,f);
	    }
		

		// Round to a specified number of decimal places

		public static function round(num: Number, dec: int):Number {
			return int(num * Math.pow(10,dec)) / Math.pow(10,dec);
		}

		// Parse JSON using fastest parser available
		
		public static function parseJSON(str:String):Object {
			try {
				var j:Object = ApplicationDomain.currentDomain.getDefinition("JSON");
				return j.parse(str);
			} catch(e:ReferenceError) {
				return com.adobe.serialization.json.JSON.decode(str);
			}
			return null;
		}

		// Simple one-line 'fetch' 
		// callback should have (data:String,success:Boolean,message:String) signature

		public static function fetch(url: String, callback: Function, binary:Boolean=false, data:String=null):void {
            var request:URLRequest = new URLRequest(url);
			var loader:URLLoader = new URLLoader();
			if (binary) loader.dataFormat="binary";
			if (data) { request.method="POST"; request.data=data; }

			loader.addEventListener(Event.COMPLETE, function(event:Event):void {
				callback(URLLoader(event.target).data, true, null);
			});
			loader.addEventListener(IOErrorEvent.IO_ERROR, function(event:Event):void {
				FlexGlobals.topLevelApplication.theController.dispatchEvent(
					new AttentionEvent(AttentionEvent.ALERT, null, "Loading error for "+url)
				);
				callback(null, false, null);
			});
			loader.addEventListener(HTTPStatusEvent.HTTP_STATUS, function(event:Event):void {
				// status event, do nothing
			});
			loader.load(request);
		}
	}
}
