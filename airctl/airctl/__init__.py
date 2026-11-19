"""airctl: CO2-driven ventilation control.

    sensor (aranet, ...) -> controller (hysteresis) -> actuator (midea_ac, kasad, none)
                                                   -> display (tivoo, none)

Each stage is chosen by `type` in config.toml; see config.example.toml.
"""

from dataclasses import dataclass, field
import time


@dataclass
class Reading:
    co2: int                      # ppm, already pressure-compensated by the sensor if it can
    temp_c: float | None = None
    humidity: float | None = None
    pressure_hpa: float | None = None
    battery: int | None = None
    source: str = ""
    at: float = field(default_factory=time.monotonic)

    @property
    def temp_f(self):
        return None if self.temp_c is None else self.temp_c * 9 / 5 + 32
