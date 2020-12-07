package com.airhttp
{
    import flash.events.Event;
    import flash.events.ProgressEvent;
    import flash.events.ServerSocketConnectEvent;
    import flash.net.ServerSocket;
    import flash.net.Socket;
    import flash.net.URLVariables;
    import flash.utils.ByteArray;
    
    import mx.controls.Alert;

    /**
    * HttpServer is a simple HTTP server capable of responding to GET requests
    * for Controllers that have been registered with it and files that can
    * be found relative to webroot under an AIR application's applicationStorage
    * directory. This server only binds to a port on localhost and is meant as
    * a way to provide access to services within/for a local process.
    * <p>
    * After construction, instances of controllers may be added to respond to
    * various HTTP GET requests. @see com.minihttp.HttpController for more on this.
    * </p>
    * <p>
    * If a matching controller to a request is found, the action (defaulting to
    * index) specified is called along with any provided parameters.
    * </p>
    * </p>
    * If no matching controller is found, the server attempts to use its FileController
    * to load the specified file (@see com.minihttp.FileController).
    * <p>
    * <p>
    * The following is a simple example showing how to initialize and start a server
    * instance. This example will respond to the urls <code>http://localhost/app/config</code>
    * and <code>http://localhost/app/status</code>.
    * </p>
    * <code>
    * ...
    *   var webserv:HttpServer = new HttpServer();
    * 
    *   webserv.registerController(new Appcontroller(myApplication));
    *   webserv.listen(4567);
    * ...
    * </code>
    * 
     */
    public class HttpServer
    {
        private var _serverSocket:ServerSocket;
        private var _mimeTypes:Object = new Object();
        private var _controllers:Object = new Object();
        private var _fileController:FileController;
        private var _errorCallback:Function = null;
        private var _isConnected:Boolean = false;
        private var _maxRequestLength:int = 2048;
        
        public function HttpServer()
        {
            _fileController = new FileController();    
        }
        
        /**
        * Retrieve the document root from the server.
         */
        public function get docRoot():String
        {
            return _fileController.docRoot;
        }
        
        public function get isConnected():Boolean
        {
            return _isConnected;
        }

        /**
        * Get the maximum lenght of a request in bytes.
        * Requests longer than this will be truncated.
        */
        public function get maxRequestLength():int
        {
          return _maxRequestLength;
        }
        
        /**
        * Set the maximum lenght of a request in bytes.
        * Requests longer than this will be truncated.
        */
        public function set maxRequestLength(value:int):void
        {
          _maxRequestLength = value;
        }
        
        /**
        * Begin listening on a specified port.
        * 
        * @param port The localhost port to begin listening on.
        * @param errorCallback The callback to call when an error occurs. If this
        * is null, an Alert box is displayed.
        * 
        * @return true if the port was opened, false if it could not be opened.
         */
        public function listen(port:int, errorCallback:Function = null):Boolean
        {
            this._errorCallback = errorCallback;
            
            try
            {
                _serverSocket = new ServerSocket();
                _serverSocket.addEventListener(Event.CONNECT, socketConnectHandler);
                _serverSocket.bind(port);
                _serverSocket.listen();
            }
            catch (error:Error)
            {
                var message:String = "Port " + port.toString() +
                    " may be in use. Enter another port number and try again.\n(" +
                    error.message +")";
                if (errorCallback != null) {
                    errorCallback(error, message);
                }
                else {
                    Alert.show(message, "Error");
                }
                return false;
            }
            return true;
        }
        
        /**
        * Add a Controller to the Server
         */
        public function registerController(controller:ActionController):HttpServer
        {
            _controllers[controller.route] = controller;
            return this;  
        }
        
        /**
        * Handle new connections to the server.
         */
        private function socketConnectHandler(event:ServerSocketConnectEvent):void
        {
            var socket:Socket = event.socket;
            socket.addEventListener(ProgressEvent.SOCKET_DATA, socketDataHandler);
        }
        
        /**
        * Handle data written to open connections. This is where the request is
        * parsed and routed to a controller.
         */
        private function socketDataHandler(event:ProgressEvent):void
        {
            try
            {
                var socket:Socket = event.target as Socket;
                var bytes:ByteArray = new ByteArray();

                // Do not read more than _maxRequestLength bytes
                var bytes_to_read:int = (socket.bytesAvailable > _maxRequestLength) ? _maxRequestLength : socket.bytesAvailable;
                
                // Get the request string and pull out the URL 
                socket.readBytes(bytes);
                var request:String          = "" + bytes;
                var url:String              = request.substring(4, request.indexOf("HTTP/") - 1);
                
                // It must be a GET request
                if (request.substring(0, 3).toUpperCase() != 'GET') {
                  socket.writeUTFBytes(ActionController.responseNotAllowed("HttpServer only supports GET requests."))
                  socket.flush();
                  socket.close();
                  return;
                }
                
                // Parse out the controller name, action name and paramert list
                var url_pattern:RegExp      = /(.*)\/([^\?]*)\??(.*)$/;
                var controller_key:String   = url.replace(url_pattern, "$1");
                var action_key:String       = url.replace(url_pattern, "$2");
                var param_string:String     = url.replace(url_pattern, "$3");
                
                var controller:ActionController = _controllers[controller_key];
                
                if (controller) {
                    param_string = param_string == "" ? null : param_string;
                    socket.writeUTFBytes(controller.doAction(action_key, new URLVariables(param_string)));
                }
                else {
                    socket.writeBytes(_fileController.getFile(url));
                }
                
                socket.flush();
                socket.close();
            }
            catch (error:Error)
            {
                if (_errorCallback != null) {
                    _errorCallback(error, error.message);
                }
                else {
                    Alert.show(error.message, "Error");
                }
            }
        }
    }
}