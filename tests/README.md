# Tests

Headless tests that run the addon against a mocked WoW client (no game needed).

```bash
lua5.1 tests/test_traits.lua .
lua5.1 tests/test_classic.lua .
lua5.1 tests/test_import.lua .
```

- `test_traits.lua` mocks WoW: Forever's trait-based talents (`C_Traits` / `C_ClassTalents`) with a Warrior.
- `test_classic.lua` mocks the classic `GetTalentInfo` / `LearnTalent` API with a Druid.
- `test_import.lua` checks Wowhead link import: real Warrior and Druid links, plus 2000 random links for trees of up to 20 talents.
