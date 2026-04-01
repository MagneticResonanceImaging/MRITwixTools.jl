# Contributing

## Development Setup

1. Clone the repository:

```bash
git clone https://github.com/JakobAsslaender/MapVBVD.jl.git
cd MapVBVD.jl
```

2. Start Julia and activate the project:

```julia
using Pkg
Pkg.develop(path=".")
Pkg.instantiate()
```

3. Run the tests:

```julia
Pkg.test("MapVBVD")
```

## Running Tests

The test suite consists of:

- **Unit tests** — no I/O, test individual types and functions
- **Integration tests** — download real `.dat` files from GitHub releases and verify correct parsing

Test data files are downloaded on first run and cached locally. SHA-256 checksums verify integrity.

To run from the command line:

```bash
julia --project -e 'using Pkg; Pkg.test()'
```

To set a custom cache directory for test data:

```bash
export MAPVBVD_TEST_DATA=/path/to/cache
julia --project -e 'using Pkg; Pkg.test()'
```

## Project Structure

See [Architecture](architecture.md) for a full codebase walkthrough.

Key points for contributors:

- **Include order matters** — see [Architecture](architecture.md) for the required order
- **Always use `getfield`** — never use `obj.field` in internal code where `getproperty` is overridden. See the [getfield rule](architecture.md#The-getfield-Rule)
- **Named constants** — use constants from `mdh_constants.jl`, don't introduce magic numbers

## Building Documentation

Documentation is built with [Documenter.jl](https://documenter.juliadocs.org/):

```bash
cd docs
julia --project make.jl
```

The built site will be in `docs/build/`. Documentation CI automatically builds on every PR and deploys to GitHub Pages on pushes to `main`.

## Pull Request Guidelines

1. **Run the full test suite** before submitting
2. **Add tests** for new functionality
3. **Follow the `getfield` rule** — see [Architecture](architecture.md)
4. **Add docstrings** for new exported functions
5. **Update documentation** if you change user-facing behavior