import Foundation

// Synthetic demo data in the exact shape the backend must return.
// Hand sample_plan.json to your backend teammate as the contract.
enum MockData {
    static let stretcherJSON = #"""
{
  "dispatch": {
    "address": "1200 Demo St, Houston, TX",
    "floor": 14,
    "unit": "1404",
    "complaint": "Cardiac arrest (synthetic call)",
    "equipment": "stretcher",
    "priority": "High"
  },
  "building": {
    "name": "Demo Tower",
    "floors": 22,
    "type": "Residential high-rise",
    "source": "synthetic"
  },
  "outdoor": {
    "route": [
      {
        "lat": 29.757,
        "lon": -95.364
      },
      {
        "lat": 29.7582,
        "lon": -95.3652
      },
      {
        "lat": 29.7594,
        "lon": -95.3665
      },
      {
        "lat": 29.7601,
        "lon": -95.3672
      }
    ],
    "staging": {
      "lat": 29.7601,
      "lon": -95.3672
    },
    "entrance": {
      "lat": 29.7604,
      "lon": -95.3676
    },
    "flags": [
      {
        "id": "f1",
        "kind": "road_work",
        "text": "Lane closure on approach street",
        "source": "TxDOT DriveTexas (sample)"
      },
      {
        "id": "f2",
        "kind": "hazard",
        "text": "Reported pothole near loading zone",
        "source": "Houston 311 (sample)"
      }
    ],
    "eta_minutes": 8,
    "distance_km": 2.4
  },
  "access": [
    {
      "id": "a1",
      "text": "Garage gate: use Knox key switch on the left post",
      "confidence": "medium",
      "synthetic": true
    },
    {
      "id": "a2",
      "text": "Lobby door code unknown: concierge desk staffed 7am to 11pm",
      "confidence": "low",
      "synthetic": true
    }
  ],
  "indoor": {
    "floor": 14,
    "width_m": 30,
    "height_m": 20,
    "rooms": [
      {
        "id": "elev",
        "name": "Elevators",
        "polygon": [
          {
            "x": 0,
            "y": 0
          },
          {
            "x": 6,
            "y": 0
          },
          {
            "x": 6,
            "y": 8
          },
          {
            "x": 0,
            "y": 8
          }
        ]
      },
      {
        "id": "r1401",
        "name": "1401",
        "polygon": [
          {
            "x": 6,
            "y": 0
          },
          {
            "x": 14,
            "y": 0
          },
          {
            "x": 14,
            "y": 8
          },
          {
            "x": 6,
            "y": 8
          }
        ]
      },
      {
        "id": "r1402",
        "name": "1402",
        "polygon": [
          {
            "x": 14,
            "y": 0
          },
          {
            "x": 22,
            "y": 0
          },
          {
            "x": 22,
            "y": 8
          },
          {
            "x": 14,
            "y": 8
          }
        ]
      },
      {
        "id": "r1403",
        "name": "1403",
        "polygon": [
          {
            "x": 22,
            "y": 0
          },
          {
            "x": 30,
            "y": 0
          },
          {
            "x": 30,
            "y": 8
          },
          {
            "x": 22,
            "y": 8
          }
        ]
      },
      {
        "id": "corr",
        "name": "Corridor",
        "polygon": [
          {
            "x": 0,
            "y": 8
          },
          {
            "x": 30,
            "y": 8
          },
          {
            "x": 30,
            "y": 12
          },
          {
            "x": 0,
            "y": 12
          }
        ]
      },
      {
        "id": "stairs",
        "name": "Stair B",
        "polygon": [
          {
            "x": 0,
            "y": 12
          },
          {
            "x": 6,
            "y": 12
          },
          {
            "x": 6,
            "y": 20
          },
          {
            "x": 0,
            "y": 20
          }
        ]
      },
      {
        "id": "r1405",
        "name": "1405",
        "polygon": [
          {
            "x": 6,
            "y": 12
          },
          {
            "x": 22,
            "y": 12
          },
          {
            "x": 22,
            "y": 20
          },
          {
            "x": 6,
            "y": 20
          }
        ]
      },
      {
        "id": "r1404",
        "name": "1404 (patient)",
        "polygon": [
          {
            "x": 22,
            "y": 12
          },
          {
            "x": 30,
            "y": 12
          },
          {
            "x": 30,
            "y": 20
          },
          {
            "x": 22,
            "y": 20
          }
        ]
      }
    ],
    "doors": [
      {
        "id": "d_elev",
        "at": {
          "x": 3,
          "y": 8
        },
        "width_in": 42,
        "passable": true
      },
      {
        "id": "d_stairs",
        "at": {
          "x": 3,
          "y": 12
        },
        "width_in": 36,
        "passable": true
      },
      {
        "id": "d_1404",
        "at": {
          "x": 26,
          "y": 12
        },
        "width_in": 36,
        "passable": true
      }
    ],
    "path": [
      {
        "x": 3,
        "y": 4
      },
      {
        "x": 3,
        "y": 10
      },
      {
        "x": 26,
        "y": 10
      },
      {
        "x": 26,
        "y": 16
      }
    ],
    "mode": "stretcher",
    "elevator_ok": true
  },
  "steps": [
    {
      "id": 1,
      "text": "Stage at the east entrance; take the lobby door",
      "seconds_min": 30,
      "seconds_max": 45
    },
    {
      "id": 2,
      "text": "Lobby to Elevator 2 (stretcher fits: 80 x 54 in car)",
      "seconds_min": 20,
      "seconds_max": 35
    },
    {
      "id": 3,
      "text": "Ride to floor 14",
      "seconds_min": 60,
      "seconds_max": 100
    },
    {
      "id": 4,
      "text": "Corridor east 35 m to unit 1404",
      "seconds_min": 46,
      "seconds_max": 48
    }
  ],
  "time": {
    "min_seconds": 156,
    "max_seconds": 228
  },
  "verification": {
    "verified": true,
    "expression": "30+20+60+46 and 45+35+100+48 (seconds)",
    "result": "156 to 228 s (2.6 to 3.8 min)"
  },
  "brief": [
    "Stage at east entrance; lane closure on approach.",
    "Gate: Knox key switch, left post (synthetic note).",
    "Elevator 2 fits the stretcher.",
    "Floor 14, corridor east, unit 1404.",
    "Estimated 2.6 to 3.8 min door to patient."
  ]
}
"""#

    static let elevatorOutJSON = #"""
{
  "dispatch": {
    "address": "1200 Demo St, Houston, TX",
    "floor": 14,
    "unit": "1404",
    "complaint": "Cardiac arrest (synthetic call)",
    "equipment": "stair_chair",
    "priority": "High"
  },
  "building": {
    "name": "Demo Tower",
    "floors": 22,
    "type": "Residential high-rise",
    "source": "synthetic"
  },
  "outdoor": {
    "route": [
      {
        "lat": 29.757,
        "lon": -95.364
      },
      {
        "lat": 29.7582,
        "lon": -95.3652
      },
      {
        "lat": 29.7594,
        "lon": -95.3665
      },
      {
        "lat": 29.7601,
        "lon": -95.3672
      }
    ],
    "staging": {
      "lat": 29.7601,
      "lon": -95.3672
    },
    "entrance": {
      "lat": 29.7604,
      "lon": -95.3676
    },
    "flags": [
      {
        "id": "f1",
        "kind": "road_work",
        "text": "Lane closure on approach street",
        "source": "TxDOT DriveTexas (sample)"
      },
      {
        "id": "f2",
        "kind": "hazard",
        "text": "Reported pothole near loading zone",
        "source": "Houston 311 (sample)"
      }
    ],
    "eta_minutes": 8,
    "distance_km": 2.4
  },
  "access": [
    {
      "id": "a1",
      "text": "Garage gate: use Knox key switch on the left post",
      "confidence": "medium",
      "synthetic": true
    },
    {
      "id": "a2",
      "text": "Lobby door code unknown: concierge desk staffed 7am to 11pm",
      "confidence": "low",
      "synthetic": true
    }
  ],
  "indoor": {
    "floor": 14,
    "width_m": 30,
    "height_m": 20,
    "rooms": [
      {
        "id": "elev",
        "name": "Elevators",
        "polygon": [
          {
            "x": 0,
            "y": 0
          },
          {
            "x": 6,
            "y": 0
          },
          {
            "x": 6,
            "y": 8
          },
          {
            "x": 0,
            "y": 8
          }
        ]
      },
      {
        "id": "r1401",
        "name": "1401",
        "polygon": [
          {
            "x": 6,
            "y": 0
          },
          {
            "x": 14,
            "y": 0
          },
          {
            "x": 14,
            "y": 8
          },
          {
            "x": 6,
            "y": 8
          }
        ]
      },
      {
        "id": "r1402",
        "name": "1402",
        "polygon": [
          {
            "x": 14,
            "y": 0
          },
          {
            "x": 22,
            "y": 0
          },
          {
            "x": 22,
            "y": 8
          },
          {
            "x": 14,
            "y": 8
          }
        ]
      },
      {
        "id": "r1403",
        "name": "1403",
        "polygon": [
          {
            "x": 22,
            "y": 0
          },
          {
            "x": 30,
            "y": 0
          },
          {
            "x": 30,
            "y": 8
          },
          {
            "x": 22,
            "y": 8
          }
        ]
      },
      {
        "id": "corr",
        "name": "Corridor",
        "polygon": [
          {
            "x": 0,
            "y": 8
          },
          {
            "x": 30,
            "y": 8
          },
          {
            "x": 30,
            "y": 12
          },
          {
            "x": 0,
            "y": 12
          }
        ]
      },
      {
        "id": "stairs",
        "name": "Stair B",
        "polygon": [
          {
            "x": 0,
            "y": 12
          },
          {
            "x": 6,
            "y": 12
          },
          {
            "x": 6,
            "y": 20
          },
          {
            "x": 0,
            "y": 20
          }
        ]
      },
      {
        "id": "r1405",
        "name": "1405",
        "polygon": [
          {
            "x": 6,
            "y": 12
          },
          {
            "x": 22,
            "y": 12
          },
          {
            "x": 22,
            "y": 20
          },
          {
            "x": 6,
            "y": 20
          }
        ]
      },
      {
        "id": "r1404",
        "name": "1404 (patient)",
        "polygon": [
          {
            "x": 22,
            "y": 12
          },
          {
            "x": 30,
            "y": 12
          },
          {
            "x": 30,
            "y": 20
          },
          {
            "x": 22,
            "y": 20
          }
        ]
      }
    ],
    "doors": [
      {
        "id": "d_elev",
        "at": {
          "x": 3,
          "y": 8
        },
        "width_in": 42,
        "passable": false
      },
      {
        "id": "d_stairs",
        "at": {
          "x": 3,
          "y": 12
        },
        "width_in": 36,
        "passable": true
      },
      {
        "id": "d_1404",
        "at": {
          "x": 26,
          "y": 12
        },
        "width_in": 36,
        "passable": true
      }
    ],
    "path": [
      {
        "x": 3,
        "y": 16
      },
      {
        "x": 3,
        "y": 10
      },
      {
        "x": 26,
        "y": 10
      },
      {
        "x": 26,
        "y": 16
      }
    ],
    "mode": "stair_chair",
    "elevator_ok": false
  },
  "steps": [
    {
      "id": 1,
      "text": "Stage at the east entrance; take the lobby door",
      "seconds_min": 30,
      "seconds_max": 45
    },
    {
      "id": 2,
      "text": "Elevators out: carry stair chair up Stair B",
      "seconds_min": 270,
      "seconds_max": 400
    },
    {
      "id": 3,
      "text": "Request extra hands for the stair carry",
      "seconds_min": 0,
      "seconds_max": 0
    },
    {
      "id": 4,
      "text": "Corridor east to unit 1404",
      "seconds_min": 60,
      "seconds_max": 65
    }
  ],
  "time": {
    "min_seconds": 360,
    "max_seconds": 510
  },
  "verification": {
    "verified": true,
    "expression": "30+270+0+60 and 45+400+0+65 (seconds)",
    "result": "360 to 510 s (6.0 to 8.5 min)"
  },
  "brief": [
    "Elevators out of service: switch to stair chair.",
    "Use Stair B, west end of each floor.",
    "Request extra hands for a 14-floor carry.",
    "Floor 14, corridor east, unit 1404.",
    "Estimated 6.0 to 8.5 min door to patient."
  ]
}
"""#
}
