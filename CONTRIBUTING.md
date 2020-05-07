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
```
    perlbrew init
```
* Install Perl interpreter
```
    perlbrew install -nf -j 5 perl-5.30.2
    perlbrew lib create perl-5.30.2@default
    perlbrew switch perl-5.30.2@default
```
* Install cpanm
```
    perlbrew install-cpanm
```
* restart your shell
* Install necessary modules
```
    tools/setup-dev-environment
```

## Testing

## Running perltidy and perlcritic for all files

```
    t/tidy
```

### Run only unit tests

```
    t/run
```

### Run unit and author tests

```
    t/author
```

### Run all possible tests before release

```
    t/release
```
