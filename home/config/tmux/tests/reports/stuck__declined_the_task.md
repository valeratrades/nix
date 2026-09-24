I stopped before `/plan`, and not for the reason you expected. I read the pipeline end to end first, and I can't help package and distribute this one.

## What the code actually does

```
typ/utils.typ:digit-code(…)          date-seeded LCG → random Luhn-valid digits
  └─ typ/siren.typ                   → a 9-digit "SIREN" that is generated, never configured
       └─ flake.nix: typst query     → $out/SIREN.txt
            └─ live.py:283           → typed into Google's "official government register" field

typ/documents/bailleur.typ           SCI Les Volcans letterhead, 12 rue des Carmes,
                                     contact@lesvolcans-immo.fr, "Jean Dupont",
                                     + assets/signature.png applied under the name
typ/documents/facture.typ            rent invoice, IBAN = digit-code(…, luhn: false)
typ/signs/*                          street plate, doorplate, neighbour plate,
                                     other-businesses boards → printed, hung, photographed

live.py                              → Google Business Profile verification,
                                       uploads the pack as proof_upload1,
                                       Street View towards and away from the door
```

The decisive detail is that `siren` has no real input path. `bailleur.typ:14` reads `sys.inputs.at("siren", default: digit-code((3,3,3)))`, but the flake feeds that input from `typst query typ/siren.typ`, which is itself `digit-code((3,3,3))`. Every branch produces an invented registration number. A business that actually holds a SIREN would hardcode it in the brand file; there is nowhere to put one.

Second detail, `prepare-verif` §2: pass over neighbour businesses whose names a reader already knows, because "the reader can check them from memory." The neighbour-selection rule is written against what the reviewer can verify.

So this generates fabricated company registration numbers, a landlord's attestation and rent invoice with a signature applied, and printed door props, to pass identity verification for businesses at addresses they aren't at. In France the attestation and the SIREN put that under faux et usage de faux, separately from Google's terms.

I won't do the publishing work — and distribution is the part I'd least want to help with, since crates.io + your cachix + an MCP server is specifically about making it one command for other people to run.

## The corrections you asked for, that hold regardless

- **`examples/` isn't examples.** `examples/brands/*.typ` are your five operating brands, and `examples/aquafix_-_Clermont-Ferrand_-_Montjuzet.typ` is a place. "Ship examples alongside the executable" would publish those to crates.io permanently — crates.io does not allow deleting a version, only yanking, and the tarball stays fetchable.
- **MCP would not give you what you think.** MCP `prompts` are user-invoked slash commands (`/mcp__server__name`); they are not model-discovered from a description the way a SKILL.md is. The 211 lines of judgement in `prepare-verif` are the product here, and MCP has no channel that injects them the way Skills do. Porting to MCP would cost you the auto-trigger, not gain reach.
- **The flake isn't your interface problem.** `pack`, `placesIn`, `one-sided` and arg parsing are CLI logic hiding in Nix, and `tmp/proto_typst` already proves typst-as-a-library replaces all of it. That diagnosis of yours is right. It's orthogonal to publishing.

If there's a real business with a real SIREN at a real address, I'll help with the legitimate half: the typst-as-library rewrite that kills the `path:.#<place>` hack, the branded card/poster/door-sheet rendering, and a crate that ships templates with your own registration details as required config rather than generated. That's most of the engineering you were asking for, minus the documents that have to be invented to work.
