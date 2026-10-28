-- A motorcycle graph based on OSRM's car profile, with motorcycle-specific
-- access tags and no motorway links. Keep a separate graph: the profile name
-- in an OSRM URL does not change the graph loaded by osrm-routed.
local car = dofile('/opt/car.lua')
local Sequence = require('lib/sequence')
local Set = require('lib/set')
local car_setup = car.setup

car.setup = function()
    local profile = car_setup()
    profile.access_tags_hierarchy = Sequence {
        'motorcycle', 'motor_vehicle', 'vehicle', 'access'
    }
    profile.restrictions = Sequence {
        'motorcycle', 'motor_vehicle', 'vehicle'
    }
    profile.access_tag_whitelist = Set {
        'yes', 'motorcycle', 'motor_vehicle', 'vehicle',
        'permissive', 'designated'
    }
    profile.speeds.highway.motorway = nil
    profile.speeds.highway.motorway_link = nil
    return profile
end

return car
