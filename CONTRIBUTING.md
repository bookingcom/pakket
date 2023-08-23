# Contributing

## Introduction

You need several applications to be able to contribute, run tests, lint and format the code

1. Perl interpreter (using perlbrew)
2. cpanm
3. modules to build the package
4. modules to run tests
5. modules to run perlcritic and perltidy

## Setup

* Install perlbrew on your system (https://perlbrew.pl/)
* Init the perlbrew (only once if you didn't have it before)
```bash
    $ perlbrew init
```
* Install perl and all necessary modules to a separate library
```bash
    $ source dev.rc
```

## Developing

Prepare your shell by running:

```bash
    $ source dev.rc
```

## Testing

### Running perltidy and perlcritic for all files

```bash
    $ make tidy
```

### Run only unit tests

```bash
    $ make unit-test
```

### Run unit and author tests

```bash
    $ make author-test
```

### Run all possible tests before release

```bash
    $ make release-test
```

## Releasing

### Prepare release archive

```bash
    $ make build
```
