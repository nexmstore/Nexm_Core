# Callbacks / RPC

Server registers `NEXM.Callback.Register(name, handler, options)`. Client calls `NEXM.Callback.Await(name, payload, options)`.

Phase 5/6 RPC direction is only client→server→client response. Callback ownership/namespacing is routing and cleanup metadata, not authorization. Server captures authoritative source, character and session. Requests and responses are bounded, rate-limited and validated. Timeouts remove pending requests; late responses are ignored.

Handlers must still enforce product business rules. RPC session checks protect transport responses but do not replace revalidation before async gameplay mutations.
