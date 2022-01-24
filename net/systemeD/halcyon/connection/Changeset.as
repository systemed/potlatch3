package net.systemeD.halcyon.connection {

    public class Changeset extends Entity {
		public static var entity_type:String = 'changeset';
		public var minLat:Number= 999;
		public var minLon:Number= 999;
		public var maxLat:Number=-999;
		public var maxLon:Number=-999;
		public var bboxInitialised:Boolean=false;

        public function Changeset(connection:Connection, id:Number, tags:Object) {
            super(connection, id, 0, tags, true, NaN, null, null);
        }

        public override function toString():String {
            return "Changeset("+id+"): "+getTagList();
        }

		public override function getType():String {
			return 'changeset';
		}

		public function get comment():String {
			var t:Object=getTagsHash();
			var s:String=t['comment'] ? t['comment'] : '';
			if (t['source']) { s+=" ["+t['source']+"]"; }
			return s;
		}
		
		public function expandBoundingBox(entity:Entity):void {
			var bbox:Object = entity.boundingBox;
			if (bbox==null) return;
			if (bbox.min_lat < minLat) minLat = bbox.min_lat;
			if (bbox.min_lon < minLon) minLon = bbox.min_lon;
			if (bbox.max_lat > maxLat) maxLat = bbox.max_lat;
			if (bbox.max_lon > maxLon) maxLon = bbox.max_lon;
			bboxInitialised = true;
		}
    }

}
