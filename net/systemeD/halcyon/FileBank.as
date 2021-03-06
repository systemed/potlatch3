package net.systemeD.halcyon {
    import flash.events.*;
	import flash.display.*;
	import flash.net.*;
	import flash.utils.ByteArray;
	import nochump.util.zip.*;
	import flash.system.LoaderContext;
	import flash.system.ApplicationDomain;
	import flash.system.SecurityDomain;

	/*
		FileBank stores and retrieves bitmap images and other files.
		Images are internally stored as Loader. Other files are stored as strings.

		See blog.yoz.sk/2009/10/bitmap-bitmapdata-bytearray/ for a really useful conversion guide!
	*/

    public class FileBank extends EventDispatcher{
		private var files:Object={};
		private var filesRequested:uint=0;
		private var filesReceived:uint=0;
		private var zipsRequested:uint=0;
		private var zipsReceived:uint=0;
        private var zipCallbacks:Array=[];
		
		public static const FILES_LOADED:String="filesLoaded";
		
		private static const GLOBAL_INSTANCE:FileBank = new FileBank();
		public static function getInstance():FileBank { return GLOBAL_INSTANCE; }

		public function hasFile(name:String):Boolean {
			if (files[name]) return true;
			return false;
		}

        public function fileLoaded(name:String, callback:Function):Boolean {
            var loaded:Boolean = false;
            if (files[name]) {
                if (files[name].hash.callbacks) {
                    files[name].hash.callbacks.push(callback);
                } else {
                    loaded = true;
                }
            }
            return loaded;
        }

        /* ==========================================================================================
		   Add an individual file to bank (not from a .zip file)
		   Used when we want to load a file for use later on (e.g. an image referenced in a stylesheet)
		   ========================================================================================== */

		public function addFromFile(filename:String, callback:Function = null):void {
            if (files[filename]) {
                if (callback != null) {
                    if (files[filename].hash.callbacks) {
                        files[filename].hash.callbacks.push(callback);
                    } else {
                        callback(this, filename);
                    }
                }
//            } else if (zipsRequested > zipsReceived) {
//                zipCallbacks.push(function ():void {
//                    addFromFile(filename, callback);
//                });
            } else {
                var request:URLRequest = new URLRequest(filename);
                var loader:Object;
                var loaderInfo:EventDispatcher;
                var lc:LoaderContext = new LoaderContext(false, new ApplicationDomain(ApplicationDomain.currentDomain));
				lc.allowCodeImport = true;
				lc.securityDomain = null;
				lc.imageDecodingPolicy = "onLoad";
				lc.applicationDomain = ApplicationDomain.currentDomain;

                if (isImageType(filename)) {
                    loader = new ExtendedLoader();
                    loaderInfo = loader.contentLoaderInfo;
                    loaderInfo.addEventListener(Event.COMPLETE, function(event:Event):void {
						var el:ExtendedLoader = loader as ExtendedLoader;
						loader.hash.bytes = el.contentLoaderInfo.bytes;
//						doCallbacks(el.hash);
//						var loader:ExtendedLoader = event.target.loader;
//						loader.hash.bytes = loader.contentLoaderInfo.bytes;
//						doCallbacks(loader.info);
			        });
                } else {
                    loader = loaderInfo = new ExtendedURLLoader();
                    loaderInfo.addEventListener(Event.COMPLETE, function(event:Event):void {
						doCallbacks(event.target.hash);
					});
                }

                loader.hash.filename = filename;
                loader.hash.callbacks = new Array();
                
                if (callback != null) {
                    loader.hash.callbacks.push(callback);
                }

                files[filename] = loader;

                loaderInfo.addEventListener(HTTPStatusEvent.HTTP_STATUS, httpStatusHandler);
                loaderInfo.addEventListener(SecurityErrorEvent.SECURITY_ERROR, securityErrorHandler);
                loaderInfo.addEventListener(IOErrorEvent.IO_ERROR, ioErrorHandler);

                filesRequested++;

				if (isImageType(filename)) {
					loader.load(request,lc);
				} else {
					// called for CSS, XML etc.
					loader.load(request);
				}
            }
		}

        public function onFilesLoaded(callback:Function):void {
            if (filesRequested > filesReceived) {
                addEventListener(FileBank.FILES_LOADED, function(e:Event):void {
                    callback();
                });
            } else {
                callback();
            }
        }

        private function doCallbacks(info:Object):void {
            var callbacks:Array = info.callbacks;
            info.callbacks = null;
            while (callbacks.length > 0) {
                var callback:Function = callbacks.shift();
                callback(this, info.filename);
            }
            checkIfLastFile();
		}
		private function httpStatusHandler(event:HTTPStatusEvent):void { }
		private function securityErrorHandler(event:SecurityErrorEvent):void { 
			checkIfLastFile();
		}
		private function ioErrorHandler(event:IOErrorEvent):void { 
			checkIfLastFile();
		}
		private function checkIfLastFile():void {
			filesReceived++;
			if (filesReceived==filesRequested) { dispatchEvent(new Event(FILES_LOADED)); }
		}

		/* ==========================================================================================
		   Add files to bank from .zip file
		   ========================================================================================== */
		
		public function addFromZip(filename:String, prefix:String=""):void {
			var loader:URLLoader = new URLLoader();
			loader.dataFormat="binary";
			loader.addEventListener(Event.COMPLETE, function(e:Event):void { zipReady(e,prefix); } );
            loader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, zipSecurityErrorHandler);
            loader.addEventListener(IOErrorEvent.IO_ERROR, zipIoErrorHandler);
            zipsRequested++;
            loader.load(new URLRequest(filename));
		}
		private function zipReady(event:Event, prefix:String):void {
			var zip:ZipFile = new ZipFile(event.target.data);
			for (var i:uint=0; i<zip.entries.length; i++) {
				var fileref:ZipEntry = zip.entries[i];
				var data:ByteArray = zip.getInput(fileref);
				if (isImageType(fileref.name)) {
					// Store as an image
					var loader:ExtendedLoader=new ExtendedLoader();
					files[prefix+fileref.name]=loader;
                    loader.hash.filename = prefix+fileref.name;
					loader.hash.bytes = data;
					loader.loadBytes(data);
				} else {
					// Store as a document
					var urlloader:ExtendedURLLoader=new ExtendedURLLoader();
					files[prefix+fileref.name]=urlloader;
                    urlloader.hash.filename = prefix+fileref.name;
                    urlloader.data = data.toString();
				}
			}
            zipReceived();
		}
		private function zipSecurityErrorHandler(event:SecurityErrorEvent):void { 
			zipReceived();
		}
		private function zipIoErrorHandler(event:IOErrorEvent):void { 
			zipReceived();
		}
		private function zipReceived():void {
			zipsReceived++;
			if (zipsReceived == zipsRequested) {
                while (zipCallbacks.length > 0) {
                    var callback:Function = zipCallbacks.shift();
                    callback();
                }
            }
		}
		private function isImageType(filename:String):Boolean {
			if (filename.match(/\.jpe?g$/i) ||
				filename.match(/\.png$/i) ||
				filename.match(/\.gif$/i) ||
				filename.match(/\.swf$/i)) { return true; }
			return false;
		}

		/* ==========================================================================================
		   Get files
		   get(filename)
		   getAsDisplayObject(filename)
		   getAsBitmapData(filename)
		   getAsByteArray(filename)
		   ========================================================================================== */

		public function get(name:String):String {
			return files[name];
		}

		public function getAsDisplayObject(name:String):DisplayObject {
			/* If the image hasn't loaded yet, then add an EventListener for when it does. */
			if (getWidth(name)==0) {
				var loader:Loader = new Loader();
				files[name].contentLoaderInfo.addEventListener(Event.COMPLETE,
					function(e:Event):void { loaderReady(e, loader) });
				return loader;
			}
			/* Otherwise, create a new Bitmap, because just returning the raw Loader
		 	   (i.e. files[name]) would only allow it to be added to one parent. (The other 
			   way to do this would be by copying the bytes as loaderReady does.). */
			return new Bitmap(getAsBitmapData(name));
		}
		
		public function getOriginalDisplayObject(name:String):DisplayObject {
			/* But if we're going to clone it later, this'll work fine. */
			return files[name];
		}

		private function loaderReady(event:Event, loader:Loader):void {
			/* The file has loaded, so we can copy the data from there into our new Loader */
			var info:LoaderInfo = event.target as LoaderInfo;
			loader.loadBytes(info.bytes);
		}

		public function getAsBitmapData(name:String):BitmapData {
			var bitmapData:BitmapData=new BitmapData(getWidth(name), getHeight(name), true, 0xFFFFFF);
			bitmapData.draw(files[name]);
			return bitmapData;
		}
		
		public function getAsByteArray(name:String):ByteArray {
			var bytes:ByteArray = files[name].hash.bytes;// || files[name].contentLoaderInfo.bytes;
			if (!bytes) { trace("-- no data for "+name+" ("+flash.utils.getQualifiedClassName(files[name])+")"); }
			return bytes;
		}
		
		public function getAsString(name:String):String {
			return files[name].data;
		}
        
		/* ==========================================================================================
		   Get file information
		   ========================================================================================== */

		public function getWidth(name:String):int { 
			try { return files[name].contentLoaderInfo.width; }
			catch (error:Error) { } return 0;
		}

		public function getHeight(name:String):int { 
			try { return files[name].contentLoaderInfo.height; }
			catch (error:Error) { } return 0;
		}

	}
}
