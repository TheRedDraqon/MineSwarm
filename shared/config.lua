local config = {
  channel = 9001,
  protocol = "mineswarm.v1",
  heartbeatSeconds = 5,
  heartbeatTimeout = 20,
  gpsTimeout = 2,
  stateFile = "/mineswarm/swarm_state",
  transitY = 250,
  lowFuel = 2000,
  refuelAtHome = true,
  maxTravelSteps = 200000,
  modemSide = nil,
}

return config
