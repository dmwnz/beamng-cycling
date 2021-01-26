angular.module('beamng.apps')
.directive('simCycling', ['$log', 'StreamsManager', function ($log, StreamsManager) {
  return {
    template:
      '<div style="width:100%; height:100%;" class="bngApp">' +
        '<table>' +
        '<tr><td>Power</td><td>{{ power || "----" }}W</td></tr>' +
        '<tr><td>Cadence</td><td>{{ cadence || "---" }}rpm</td></tr>' +
        '<tr><td>Speed</td><td>{{ speed || "---" }}km/h</td></tr>' +
        '<tr><td>Heartrate</td><td>{{ heartrate || "---" }}bpm</td></tr>' +
        '<tr><td>Slope</td><td>{{ slope || "---" }}%</td></tr>' +
        '<tr><td>Slope (smoothed)</td><td>{{ slope_smoothed || "---" }}%</td></tr>' +
        '</table>' +
      '</div>',
    replace: true,
    restrict: 'EA',
    link: function (scope, element, attrs) {
      'use strict';
      StreamsManager.add(['electrics']);
      scope.$on('$destroy', function () {
        $log.debug('<sim-cycling> destroyed');
        StreamsManager.remove(['electrics']);
      });

      scope.power = 0;
      scope.cadence = 0;
      scope.speed = 0;
      scope.heartrate = 0;
      scope.slope = 0;

      scope.$on('streamsUpdate', function (event, streams) {  
        scope.$evalAsync(function () {
          scope.power = Math.round(streams.electrics.ant_power);
          scope.cadence = Math.round(streams.electrics.ant_cadence);
          scope.speed = Math.round(streams.electrics.ant_speed * 10)/10.0;
          scope.heartrate = Math.round(streams.electrics.ant_heartrate); 
          scope.slope = Math.round(Math.tan(streams.sensors.pitch) * 1000)/10; 
          scope.slope_smoothed = Math.round(streams.electrics.ant_slope * 10)/10; 
        });
      });
    }
  };
}]);