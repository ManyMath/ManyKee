# Vendored Cargokit local patch

`cargokit/build_pod.sh`: remove the unconditional `env` dump so native Apple
builds cannot print caller credentials into CI logs. Keep this patch when
synchronizing the pinned vendored Cargokit source. No build invocation, target
selection or public API changes.

The payload gate preflights only the host architecture for Flutter debug macOS
consumers, matching the pinned SDK's build_macos.dart behavior. Release or
universal builds need a separate explicit target contract and evidence.
