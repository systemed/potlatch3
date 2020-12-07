package com.airhttp
{
    import flash.net.URLVariables;

    /**
    * ActionController is the base class for all web requests
    * processed by <code>com.airhttp.HttpServer</code>. Implementers
    * will subclass <code>ActionController</code> to provide the
    * implementation required for thier application.
    * <p>
    * The general approach is to subclass and provide a unique
    * <code>route</code> for actions to be invoked on thier controller.
    * If no specific action name is determined by <code>com.airhttp.HttpServer</code>,
    * the <code>index</code> method is called, otherwise the action name
    * must match the name of the specified ActionControler's methods.
    * </p>
    * </p>
    * Each action expects to be called with an instance of URLVariables
    * as the parameters passed in the URL and will return a String or
    * ByteArray with a complete <code>HTTP 1.1</code> response that
    * signals success or failure.
    * </p>
    * <p>
    * Several methods have been provided to simplify this.
    * @see responseSuccess
    * @see responseNotFound
    * @see responseForbidden
    * @see response
    * @see header
    * </p>
     */
    public class ActionController
    {    
        private var _route:String;
        
        /**
        * @param route is the string to match to signify that
        * this is the controller to use for a request. Be
        * certain to make this unique for your application.
         */
        public function ActionController(route:String = "/")
        {
            _route = route;
        }
        
        /**
        * Subsclasses may set the route for this ActionController
         */
        protected function set route(value:String):void
        {
            _route = value;
        }
        
        /**
        * Retrieve the route for this controller.
         */
        public function get route():String
        {
            return _route;
        }
        
        /**
        * The main entry point for calling an action by the <code>HttpServer</code>
         */
        public function doAction(action:String, params:URLVariables):String
        {
            if (action == "") {
                action = "index";
            }
            
            if (!(this[action] is Function)) {
                return actionNotFound(action);
            }
            return this[action].call(this, params);
        }
        
        /**
        * The default implementation for <code>index</code>
         */
        public function index(params:URLVariables):String
        {
            return responseSuccess("");
        }
        
        /**
        * Convenience function to respond with success.
        * 
        * @param content is the HTML content to return
        * @param mimeType is the mime-type (default to "text/html"
        * 
        * @returns a String with the successful response.
         */
        protected static function responseSuccess(content:String, mimeType:String = "text/html"):String
        {
            return response(200, "OK", content, mimeType);    
        }
        
        /**
         * Convenience function to respond when the specified action
         * isn't found.
         * 
         * @param content is the HTML error message to be displayed.
         * 
         * @returns a String with the error response.
         */
        protected static function actionNotFound(action:String):String
        {
            var s:String = "Action: " + action + " Not Found"
            return responseNotFound(s);
        }
        
        /**
         * Convenience function to respond when a resource isn't found.
         * 
         * @param content is the HTML error message to be displayed.
         * 
         * @returns a String with the error response.
         */
        protected static function responseNotFound(content:String):String
        {
            return response(404, "Not Found", content);    
        }
        
        /**
         * Convenience function to respond when a resource is forbidden.
         * 
         * @param content is the HTML error message to be displayed.
         * 
         * @returns a String with the error response.
         */
        protected static function responseForbidden(content:String):String
        {
            return response(403, "Forbidden", content);    
        }
        
        /**
         * Convenience function to respond when a Resource is Not Allowed.
         * 
         * @param content is the HTML error message to be displayed.
         * 
         * @returns a String with the error response.
         */
        public static function responseNotAllowed(content:String):String
        {
            return response(405, "Method Not Allowed", content);    
        }
        
        /**
         * Convenience function to respond to a web request.
         * 
         * @param code is the HTTP header response code
         * @param message is a String with the message associated with code in the HTTP header
         * @param content is the HTML to display on the response page.
         * @param mimeType is the mime-type associaged the the response page.
         * 
         * @returns a String with the error response.
         */
        protected static function response(code:int, message:String = "", content:String = "", mimeType:String = "text/html"):String
        {
            return header(code, message, mimeType) + content; 
        }
        
        /**
         * Convenience function to format an HTTP 1.1 header.
         * 
         * @param code is the HTTP header response code
         * @param message is a String with the message associated with code in the HTTP header
         * @param mimeType is the mime-type associaged the the response page.
         * 
         * @returns a String with the HTTP 1.1 header
         */
        protected static function header(code:int, message:String = "", mimeType:String = "text/html"):String
        {
            return "HTTP/1.1 " + code.toString() + " " + message + "\n" + "Content-Type: " + mimeType + "\n\n";             
        }
    }
}