# IoT Sensor Order Audit

## Core invariant

For telemetry systems whose payload identifies channels with `sensor_pin` or an equivalent SNR/channel field, resolve identity by `(device_id, physical_pin)`. Do not infer identity from JSON array position, database row order, installation ID, or serial ordering. A device can remain online while a changed pairing silently stores readings under the wrong asset.

## Read-only audit sequence

1. Read model capabilities ordered by physical `pin`.
2. Join installed sensors to the device, physical pin, current asset, and active serial/name configuration.
3. Compare the current serial-per-pin map with the last known-good map.
4. Inspect `configuracion_activa_sensor` history by sensor and parameter using activation timestamps and active flags; current rows may have overwritten prior values.
5. Separate device measurement time from server reception time because delayed payloads may arrive after a configuration change.

## Ingestion-code check

Every configuration array item must be scoped to its declared pin before upsert. Iterating over every sensor of a functionality for every payload item is a cross-sensor overwrite defect. Add a three-sensor permutation fixture and assert configuration isolation and correct asset mapping.

## Repair rule

Prefer changing the pin-to-asset assignment or restoring the device pairing order. Do not mutate physical pin metadata merely to compensate for a reorder. Produce a read-only before/after mapping and obtain explicit approval before any production DB write.

## ThermalTrack incident pattern

The relevant production shape was device `60`, with installed sensors `5402`, `5403`, and `5404` on pins 1–3. The last-known-good serial mapping was:

```text
pin 1 / 5402 -> 287696B305000033 -> CAVA 3
pin 2 / 5403 -> 28EEFCB30500008F -> CAVA 1
pin 3 / 5404 -> 281438B30500000F -> CAVA2
```

A later device re-pair produced:

```text
pin 1 / 5402 -> 28EEFCB30500008F
pin 2 / 5403 -> 281438B30500000F
pin 3 / 5404 -> 287696B305000033
```

The backend resolved readings by `sensoresByPin.get(pin)` and stored them under the installed sensor for that pin. Therefore the platform-side compensating assignment would be `5402 -> CAVA 1`, `5403 -> CAVA2`, `5404 -> CAVA 3`, unless the device pairing is restored instead.

Also verify threshold/configuration history: a configuration ingestion loop that processes every sensor row for every array item can overwrite a sibling sensor's limits and identifiers. Compare each parameter's current value and activation timestamp before proposing restoration.