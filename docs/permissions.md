# Permissions

Server-only definitions are resource-owned:

```lua
NEXM.Permissions.Define('manage', {
  mode = 'any',
  ace = { 'nexm.example.manage' },
  jobs = { police = { minimumGrade = 3, requireDuty = true } }
})
```

Check with `Has(source, name)` or `HasAny(source, names)`. Providers include ACE, normalized job/grade/duty, reliable framework permission/group support, and protected custom resolvers. Unknown permissions fail closed with `PERMISSION_NOT_DEFINED`. Ordinary denial is `false,nil`.
