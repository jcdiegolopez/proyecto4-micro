/******************************************************
* Universidad del Valle de Guatemala
* Facultad de Ingeniería
* Curso: Microprocesadores
* Proyecto: Integración MPU6050, sensor de pulso cardiaco
*
* Fecha: 15 Noviembre 2024
*
* Descripción: Envío de lecturas de temperatura y 
			   humedad desde un sensor DHT11 conectado 
			   a un ESP8266 hacia Google Sheets 
			   mediante Google Apps Script​
*******************************************************/

function doGet(e) { 
  Logger.log( JSON.stringify(e) );
  var result = 'Ok';
  if (e.parameter == 'undefined') {
  result = 'No Parameters';
  }
  else {
    var sheet_id = '1tLuT1a2bAj8LWGsPxyQq2jRIpcrHd_ilcCmQvuqvklA'; //COMPLETAR CON Spreadsheet ID
    var sheet = SpreadsheetApp.openById(sheet_id).getActiveSheet();
    var newRow = sheet.getLastRow() + 1; 
    var rowData = [];
    var Curr_Date = new Date();
    rowData[0] = Curr_Date; // Date in column A
    var Curr_Time = Utilities.formatDate(Curr_Date, "America/Guatemala", "HH:mm:ss");
    rowData[1] = Curr_Time; // Time in column B
    for (var param in e.parameter) {
      Logger.log('In for loop, param=' + param);
      var value = stripQuotes(e.parameter[param]);
      Logger.log(param + ':' + e.parameter[param]);
        switch (param) {
          case 'bpm':
          rowData[2] = value; // Temperature in column C
          result = 'bmp Written on column C'; 
          break;
        case 'acelx':
          rowData[3] = value; // Pressure in column D
          result += 'Acceleration x Written on column D'; 
          break;
        case 'acely':
          rowData[4] = value; // Pressure in column D
          result += 'Acceleration y Written on column E'; 
          break;
        default:
          result = "unsupported parameter";
      }
    }
    Logger.log(JSON.stringify(rowData));
    var newRange = sheet.getRange(newRow, 1, 1, rowData.length);
    newRange.setValues([rowData]);
  }
  return ContentService.createTextOutput(result);
  }
  function stripQuotes( value ) {
  return value.replace(/^["']|['"]$/g, "");
}
