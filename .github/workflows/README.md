# Our Workflows

## Unit Test
[![Unit Test](https://github.com/shaave/v1-core/actions/workflows/test.yml/badge.svg)](https://github.com/shaave/v1-core/actions/workflows/test.yml)

This action tests our code using Foundry's `forge test` [testing tool](https://book.getfoundry.sh/forge/tests).

Local Unit Test runs for every push and every pull request on all branches of v1-core in Github Actions.

## Format Check
[![Format Check](https://github.com/shaave/v1-core/actions/workflows/format-check.yml/badge.svg)](https://github.com/shaave/v1-core/actions/workflows/format-check.yml)

This action uses Foundry's `forge fmt` [formatter](https://book.getfoundry.sh/static/config.default.toml) to check for format errors.