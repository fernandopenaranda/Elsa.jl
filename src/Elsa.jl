module Elsa

using StaticArrays, NearestNeighbors, SparseArrays, LinearAlgebra, OffsetArrays,
      FFTW, ProgressMeter

import Base: convert, iterate, ==, tail
import SparseArrays: sparse!, mul!, getcolptr

export sublat, bravais, lattice, hopping, onsite, hamiltonian, randomstate,
       mul!, supercell, unitcell, iscompatible, bloch
    #    unitlattice, combine, transform, transform!, bound,
    #    sitepositions, neighbors, bravaismatrix, marchingmesh
# export MomentaKPM, dosKPM
export LatticePresets, RegionPresets

export @SMatrix, @SVector, SMatrix, SVector

# const NameType = String
# const nametype = string
const NameType = Symbol
const nametype = Symbol

include("iterators.jl")
include("presets.jl")
include("lattice.jl")
include("model.jl")
include("field.jl")
include("hamiltonian.jl")
# include("system.jl")
include("state.jl")
# include("operators.jl")
# include("system.jl")
# include("system_methods.jl")
# include("KPM.jl")
# include("mesh.jl")
# include("bandstructure.jl")
include("convert.jl")
include("tools.jl")

end
