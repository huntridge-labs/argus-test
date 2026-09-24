# The leg of D5 that DIES WITHOUT WRITING RESULTS.
#
# The base image does not exist and the registry host does not resolve, so
# `docker build` fails before any layer is produced. The scan step for this leg
# never runs, so no argus-results.json is written for it and container-scan.yml
# publishes its argus_scan_incomplete sentinel instead.
#
# This is an induced failure, not a mock: the build genuinely fails the way a
# consumer's build fails when a base image is withdrawn or a registry is
# unreachable. Nothing here stubs argus or edits its output.
FROM nonexistent-registry.invalid/no-such-image:v0.0.0
RUN echo "d5-fails: unreachable, this never executes"
