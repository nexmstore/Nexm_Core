# Versions

`NEXM.Version.Get`, `Compare`, `Satisfies`, and `Require` use the Core SemVer implementation. Supported constraints include comparison operators, compound ranges, tilde, caret and `||` alternatives.

Resource version is the product release version. Service `apiVersion` is a separate integer compatibility contract; do not treat the two as interchangeable.

## Release-candidate policy

The current MVP release-candidate line is `1.0.0-rc.1`; the packaged build is `1.0.0-rc.1.hotfix.3`. It intentionally does not satisfy a strict `>=1.0.0` requirement. Products explicitly accepting prerelease Core builds may use a compatible prerelease range such as `>=1.0.0-0` during RC validation.

The internal `BUILD_ID` is a diagnostic fingerprint and is not a replacement for public SemVer. Final `1.0.0` requires separate release authorization after the RC publication gate and any chosen soak period.

For future deprecations, 1.x should preserve compatibility; intentional breaking contracts move to 2.0.
