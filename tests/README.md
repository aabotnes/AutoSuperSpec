# Tests

Headless tests that run the addon against a mocked WoW client (no game needed).

```bash
lua5.1 tests/test_traits.lua .
lua5.1 tests/test_classic.lua .
```

- `test_traits.lua` mocks WoW: Forever's trait-based talents (`C_Traits` / `C_ClassTalents`) with a Warrior.
- `test_classic.lua` mocks the classic `GetTalentInfo` / `LearnTalent` API with a Druid.
