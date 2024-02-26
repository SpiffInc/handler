# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.5.0] - 2024-02-26

We added a `pool_timeout: milliseconds` option to the `Pool.run` and `Pool.async` functions which allows us to adjust the communication timeout of kicking off work in a pool.
The Pool should always be responsive, but if the schedulers are very busy we still need to account for a failure to communicate with the Pool.
We will now return a `{:reject, Handler.Pool.Timeout.exception(...)}` when this happens so calling code can more easily handle this edge case.

## [0.4.3] - 2023-04-18

### Fixed
- Fixed incompatibility with Elixir 1.14

## [0.4.2] - 2022-08-25

### Added
- tests
