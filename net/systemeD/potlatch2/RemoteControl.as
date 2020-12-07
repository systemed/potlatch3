package net.systemeD.potlatch2 {

	import com.airhttp.*;
	import flash.net.URLVariables;

	/* To do:
		- do zoom level too
		- cope with select=way38473,node12399,node54646
		- send Content-Length like a good little server
	   (See docs at https://wiki.openstreetmap.org/wiki/JOSM/RemoteControl) */
	

	public class RemoteControl extends com.airhttp.ActionController {

		private var ec:EditController;
		
		public function RemoteControl(_ec:EditController) {
			super('');
			ec=_ec;
		}
		
		public function load_and_zoom(params:URLVariables):String {
			var lon:Number = (Number(params.left)+Number(params.right)) / 2;
			var lat:Number = (Number(params.top)+Number(params.bottom)) / 2;
			ec.map.moveMapFromLatLonDefaultScale(lat,lon);
			return responseSuccess("OK", "text/plain");
		}
	}
}
