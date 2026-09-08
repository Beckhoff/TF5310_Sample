(function (TcHmi) {
	//Register to the global onInitialized event, the anonymous function will be called only one time and will check the parameter of the url and reloads the page depending on the parameter

	let destr = TcHmi.EventProvider.register("onInitialized", function () {
		// This event will be raised only once, so it is nice to cleanup
		destr();

		//Get the complete url from browser and splitting the url at "?" in an array, e.g. http://127.0.0.1:1010/?View=View1
		let paramArray = window.location.href.split('?');
		//Create temp variables for the path parameter
		let pathParam = "";

		//Search in paramArray of splitted url for 'View=', e.g. "View=View1"
		for (i = 0; i < paramArray.length; i++) {
			if (paramArray[i].indexOf('View=') === 0) {
				pathParam = paramArray[i].split('/').join('');
				break;
			}
		}
		
		//Setting of viewName depending on pathParam
		if (pathParam === "View=3D" || pathParam === "view=3d" || pathParam === "View=3d") {
			TcHmi.View.load('Simulation3D.view', function (data) {
				//Optional: Callback after the page is loaded
			});
		}

		//var msgBoxControl = TcHmi.ControlFactory.createEx('TcHmi.Controls.TcHmiCncBase.TcHmiCncMessageBox',
		//	'CncMsgBox',
		//	{
		//		'data-tchmi-top': 25,
		//		'data-tchmi-left': 250,
		//		'data-tchmi-width': '100',
		//		'data-tchmi-width-unit' : '%',
		//		'data-tchmi-height': '100',		
		//		'data-tchmi-height-unit': '%',
		//		'data-tchmi-background-color': {
		//			'color': 'transparent'
		//		}
		//	}
		//);
						
		//TcHmi.TopMostLayer.addEx(msgBoxControl.getElement(), {
		//	centerHorizontal: true,
		//	centerVertical: true,
		//	modal: false,
		//	dimBackground: false,
		//	removeCb: (data) => {
		//		if (data.canceled) {
		//			// user clicked on background
		//		}
		//	}
		//});



		//TcHmi.EventProvider.register('Desktop.onAttached', function (e, data) {

		//	let msgBoxControl = TcHmi.ControlFactory.createEx('TcHmi.Controls.TcHmiCncBase.TcHmiCncMessageBox',
		//		'CncMsgBox',
		//		{
		//			'data-tchmi-top': 0,
		//			'data-tchmi-left': 0,
		//			'data-tchmi-width': '100',
		//			'data-tchmi-width-unit': 'px',
		//			'data-tchmi-height': '200',
		//			'data-tchmi-height-unit': 'px',
		//			'data-tchmi-background-color': {
		//				'color': 'transparent'
		//			}
		//		}
		//	);			
		//	data.addChild(msgBoxControl);
		//});



		//else if (pathParam === "View=Tablet") {
		//	TcHmi.View.load('Tablet.view', function (data) {
		//		//Optional: Callback after the page is loaded
		//	});
		//}
		//else if (pathParam === "View=Mobile") {
		//	TcHmi.View.load('Mobile.view', function (data) {
		//		//Optional: Callback after the page is loaded
		//	});
		//}

		//Optional: direct mode, no fallback if view does not exist
		//let viewName = pathParam.substr(pathParam.indexOf("=") + 1);
		//TcHmi.View.load(viewName + '.view', function (data) {
		//Optional: Callback after the page is loaded
		//});		
	});
})(TcHmi);
