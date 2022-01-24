package net.systemeD.halcyon.connection {

	import net.systemeD.halcyon.connection.actions.*;

    public class Relation extends Entity {
        private var members:Array;
		public static var entity_type:String = 'relation';

        public function Relation(connection:Connection, id:Number, version:uint, tags:Object, loaded:Boolean, members:Array, uid:Number = NaN, timestamp:String = null, user:String = null) {
            super(connection, id, version, tags, loaded, uid, timestamp, user);
            this.members = members;
			for each (var member:RelationMember in members)
			    member.entity.addParent(this);
        }

        public function update(version:uint, tags:Object, loaded:Boolean, parentsLoaded:Boolean, members:Array, uid:Number = NaN, timestamp:String = null, user:String = null):void {
			var member:RelationMember;
			for each (member in this.members)
			    member.entity.removeParent(this);

			updateEntityProperties(version,tags,loaded,parentsLoaded,uid,timestamp,user);
			this.members=members;
			for each (member in members)
			    member.entity.addParent(this);
		}
		
        public function get length():uint {
            return members.length;
        }

		public function get memberEntities():Array {
			var list:Array=[];
			for (var index:uint = 0; index < members.length; index++) {
				var e:Entity=members[index].entity;
				if (list.indexOf(e)==-1) list.push(e);
			}
			return list;
		}
		
        public function findEntityMemberIndex(entity:Entity):int {
            for (var index:uint = 0; index < members.length; index++) {
                var member:RelationMember = members[index];
                if ( member.entity == entity )
                    return index;
            }
            return -1;
        }

        public function findEntityMemberIndexes(entity:Entity):Array {
            var indexes:Array = [];
            for (var index:uint = 0; index < members.length; index++) {
                var member:RelationMember = members[index];
                if ( member.entity == entity )
                    indexes.push(index);
            }
            return indexes;
        }
        
        public function getMember(index:uint):RelationMember {
            return members[index];
        }

		public function getFirstMember():RelationMember {
			return members[0];
		}

		public function getLastMember():RelationMember {
			return members[members.length-1];
		}

        public function setMember(index:uint, member:RelationMember, performAction:Function):void {
            var composite:CompositeUndoableAction = new CompositeUndoableAction("Set Member at index "+index);
            composite.push(new RemoveMemberByIndexAction(this, members, index));
            composite.push(new AddMemberToRelationAction(this, index, member, members));
            performAction(composite);
        }

		public function findMembersByRole(role:String, entityType:Class=null):Array {
			var a:Array=[];
            for (var index:uint = 0; index < members.length; index++) {
                if (members[index].role==role && (!entityType || members[index].entity is entityType)) { a.push(members[index].entity); }
            }
			return a;
		}

		/** Is there an entity member in this specific role? */
		public function hasMemberInRole(entity:Entity,role:String):Boolean {
            for (var index:uint = 0; index < members.length; index++) {
				if (members[index].entity == entity && members[index].role==role) { return true; }
			}
			return false;
		}
		
        public function insertMember(index:uint, member:RelationMember, performAction:Function):void {
            performAction(new AddMemberToRelationAction(this, index, member, members));
        }

        public function appendMember(member:RelationMember, performAction:Function):uint {
            performAction(new AddMemberToRelationAction(this, -1, member, members));
            return members.length + 1;
        }

		public function removeMember(entity:Entity, performAction:Function):void {
			if (length>1) {
				performAction(new RemoveEntityFromRelationAction(this, entity, members));
			} else {
				performAction(new DeleteRelationAction(this, setDeletedState, members));
			}
		}

        public function removeMemberByIndex(index:uint, performAction:Function):void {
			if (length>1) {
				performAction(new RemoveMemberByIndexAction(this, members, index));
			} else {
				performAction(new DeleteRelationAction(this, setDeletedState, members));
			}
        }

		public override function remove(performAction:Function):void {
			performAction(new DeleteRelationAction(this, setDeletedState, members));
		}

		public override function nullify():void {
			nullifyEntity();
			members=[];
		}
		
		internal override function isEmpty():Boolean {
			return (deleted || (members.length==0));
		}

		public override function getDescription():String {
			var desc:String = "";
			var relTags:Object = getTagsHash();
			var named:Boolean = false;
			if ( relTags["type"] ) {
				// type=route				--> "route"
				desc = relTags["type"];
				// type=route, route=bicycle--> "route bicycle"
				if (relTags[desc]) { desc += " " + relTags[desc]; }
			}
			// type=route, route=bicycle, network=ncn, ref=54 -> "route bicycle ncn 54"
			if ( relTags["network"]) { desc += " " + relTags["network"]; }
			if ( relTags["ref"]    ) { desc += " " + relTags["ref"];  named=true; }
			if ( relTags["name"]   ) { desc += " " + relTags["name"]; named=true; }
			// handle node->node routes
			if ( !named && relTags["type"] && relTags["type"]=="route" ) {
				var firstName:String=getSignificantName(getFirstMember().entity);
				var lastName:String=getSignificantName(getLastMember().entity);
				if ((firstName+lastName)!='') desc+=" "+firstName+"-"+lastName;
			}
			return desc;
		}
		
		public function getRelationType():String {
			var relTags:Object = getTagsHash();
			return relTags["type"] ? relTags["type"] : getType();
		}
		
		public function hasKeysOtherThanType():Boolean {
			// used for detecting old-style vs new-style multipolygons
			for (var key:String in getTagsHash()) {
				if (key!='type' && key!='created_by' && key!='source') { return false; }
			}
			return true;
		}

		private function getSignificantName(entity:Entity):String {
			if (!entity.loaded || (entity is Relation)) return '';

			var t:String;
			if (entity is Way) {
				t=getSignificantName(Way(entity).getFirstNode());
				if (t=='') t=getSignificantName(Way(entity).getLastNode());
				return t;
			}
			t=Node(entity).getTag('name');
			if (!t) t=Node(entity).getTagByRegex(/ref$/);
			return t ? t : '';
		}

		public override function getType():String {
			return 'relation';
		}
		
		public override function toString():String {
            return "Relation("+id+"@"+version+"): "+members.length+" members "+getTagList();
        }

    }

}
