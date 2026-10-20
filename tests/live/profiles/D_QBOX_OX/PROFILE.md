# D_QBOX_OX

Status: `NOT EXECUTED`

Record before testing:

- FXServer artifact/build: `<record>`
- OS: `<record>`
- Database + exact version: `<record>`
- oxmysql version: `<record>`
- Framework: Qbox/QBX — exact version/commit `<record>`
- Inventory: ox_inventory — exact version/commit `<record>`
- Notify: Qbox/ox_lib — exact version/commit `<record>`
- NEXM Core artifact SHA-256: `<record>`
- OneSync: `<record>`
- Player slots: `<record>`

Suggested ensure order:

```cfg
ensure oxmysql
# ensure framework and its required dependencies
# ensure selected inventory
# ensure selected notify provider
ensure nexm_core
ensure nexm_core_test
```

Do not place secrets or license keys in committed profile files.
