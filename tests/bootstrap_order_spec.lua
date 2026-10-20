local expected = {
    'STATE:DATABASE','DB_CONNECT','STATE:MIGRATING','MIGRATION_TABLE','CORE_MIGRATIONS',
    'ADAPTER_REGISTRY','STATE:FRAMEWORK','FRAMEWORK_INIT','STATE:PLATFORM',
    'LIFECYCLE_SUBSCRIBE','PLAYER_CACHE_RECONSTRUCT','INVENTORY_INIT','NOTIFY_INIT','AUDIT_INIT','DIAGNOSTICS','STATE:READY','READY_EVENT'
}
local actual=NEXM_TEST_BOOT_ORDER or {}; local failed=0
for index,value in ipairs(expected) do
    local ok=actual[index]==value
    print(('[%s] bootstrap order %02d expected=%s actual=%s'):format(ok and 'PASS' or 'FAIL',index,value,tostring(actual[index])))
    if not ok then failed=failed+1 end
end
local lengthOk = #actual == #expected
print(('[%s] bootstrap order length expected=%d actual=%d'):format(lengthOk and 'PASS' or 'FAIL', #expected, #actual))
if not lengthOk then failed=failed+1 end
if failed>0 then error(('Bootstrap order tests failed: %d'):format(failed)) end
print(('Tests: %d, Failed: 0'):format(#expected+1))
