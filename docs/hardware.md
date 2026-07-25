# Target hardware

## Primary kit

| Item | Value |
|------|--------|
| Kit | AMD Virtex UltraScale+ HBM **VCU128** FPGA Evaluation Kit |
| FPGA | **VU37P** (UltraScale+) |
| Rivet PHY | `rivet_pcie_phy_usplus` (`FPGA_FAMILY=0` on `rivet_pcie`) |

VCU128 is the reference platform for Phase 2+ FPGA bring-up (full `rivet_pcie` + PG239).

## Alternate kit

| Kit | Notes |
|-----|--------|
| AMD Virtex UltraScale+ 56G PAM4 **VCU129-PP** | Acceptable if VCU128 cannot be obtained; prefer VCU128 |

## Sponsorship

Open-source Rivet development needs access to a **VCU128** (or loan/donation of an equivalent UltraScale+ PCIe board). See the README support section.

## Specs and vendor IP

- Keep proprietary PDFs under local `specs/` (gitignored; never commit).
- Generated / encrypted PHY and BFM material stays under `third_party/` per existing ignore rules.
