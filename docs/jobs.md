# Jobs

`NEXM.Jobs.Get`, `Has`, `HasAny`, `MinimumGrade`, and `IsOnDuty` operate on the normalized primary job from the selected framework.

Duty semantics are explicit: on duty → `true,nil`; off duty → `false,nil`; unsupported duty → `nil,UNSUPPORTED_FEATURE`. Permissions that require duty grant only when authoritative duty is exactly true.
