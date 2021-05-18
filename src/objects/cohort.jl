mutable struct Cohort
    animals     ::Array{Animal, 1}
    n           ::Int64

    # Null Constructor
    Cohort() = new()

    ```Initiate cohorts with sampled genotypes```
    function Cohort(;n_founders ::Int64)
        cohort = Array{Animal}(undef, n_founders)
        for i in 1:n_founders
            cohort[i] = Animal(Animal(), Animal())
        end

        return new(cohort, n_founders)
    end

    ```Initiate cohorts with given genotypes```
    function Cohort(genotypes   ::Union{DataFrame, Array{Int64}})
        if isa(genotypes, DataFrame)
            n_founders = nrow(genotypes)
            n_loci     = ncol(genotypes)

        elseif isa(genotypes, Array)
            n_founders = size(genotypes, 1)
            n_loci     = size(genotypes, 2)

        else
            error("Input genotypes not supported")
        end

        if n_loci != GLOBAL("n_loci")
            error("Number of loci mismatches the given genome")
        end

        cohort        = Array{Animal}(undef, n_founders)
        for i in 1:n_founders
            hap       = vcat(genotypes[i, :]...)
            cohort[i] = Animal(Animal(), Animal(), haplotypes=hap)
        end

        return new(cohort, n_founders)
    end

    function Cohort(filename    ::String)
        return cohort(CSV.read(filename, DataFrame,
                               header=false, missingstrings=["-1", "9"]))
    end

    # Constructor for non-founder
    function Cohort(animals     ::Array{Animal, 1})
        n = length(animals)
        return new(animals, n)
    end

    function Cohort(animal      ::Animal)
        return new([animal], 1)
    end
end

Founders(genotypes::Union{DataFrame, Array{Int64}}) = Cohort(genotypes)
Founders(filename ::String)                         = Cohort(filename)
Founders(n        ::Int64)                          = Cohort(n_founders=n)

function Base.summary(cohort::Cohort; is_return=true)
    bvs        = get_BVs(cohort)
    mu_g       = XSim.mean(bvs, dims=1)
    var_g      = XSim.var(bvs,  dims=1)

    if is_return
        return Dict([("n"   , cohort.n),
                     ("Mu_g", mu_g),
                     ("Var_g", var_g)])
    else
        println("Cohort (", cohort.n, " individuals)")
        println()
        print(  "Mean of breeding values    : ")
        display(mu_g)
        println()
        print(  "Variance of breeding values: ")
        display(var_g)
    end
end

function get_QTLs(cohort::Cohort)
    return get_genotypes(cohort)[:, GLOBAL("is_QTLs")]
end

function get_genotypes(cohort::Cohort)
    genotypes_2d = (animal->get_genotypes(animal)).(cohort)

    return hcat(genotypes_2d...)'
end

function get_BVs(cohort::Cohort)
    bv_2d = (animal->get_BVs(animal)).(cohort)
    return hcat(bv_2d...)'
end

# available types: phenotypic, genotypic, estimated
function get_phenotypes(cohort::Cohort;
                        h2    ::Union{Array{Float64}, Float64}=.5,
                        Ve    ::Union{Array{Float64}, Float64}=-999.99)

    traits_2d = (animal->get_phenotypes(animal, h2=h2, Ve=Ve)).(cohort)
    # return a n by p matrix
    return hcat(traits_2d...)'
end

function get_IDs(cohort::Cohort)
    return (animal->animal.ID).(cohort)
end

function get_pedigree(cohort::Cohort)
    # return a 3-column matrix: ID, SireID, DamID
    ped = (animal->[animal.ID, animal.sire.ID, animal.dam.ID]).(cohort)
    return hcat(ped...)'
end

function get_DH(parents::Cohort, n::Int64)
    animals = Array{Animal}(undef, n)
    select_idx = sample(parents.n, n, replace=true)
    for i in 1:nDHs
        parent = parents[select_idx[i]]
        animals[i] = get_DH(parent)
    end
    return cohort(animals)
end

function get_haplotype_founder(cohort::Cohort)
    haps = []
    for animal in cohort
        for chromosome in [animal.genome_sire; animal.genome_dam]
            for ori in chromosome.ori
                push!(haps, ori)
            end
        end
    end
    haps
end

# ped, mme, out is from JWAS get_pedigree(), build_model(), and solve()
function putEBV(cohort::Cohort, ped, mme, out)
    # transfer ebv from mme to XSim
    trmAnimal = mme.modelTermDict["1:Animal"]
    for animal in cohort
        id = animal.ID
        strID = string(id)
        mmePos = ped.idMap[strID].seqID + trmAnimal.startPos - 1
        animal.traits[1].estimated = out[mmePos, 2]
    end
end

function sample(cohort ::Cohort,
                n      ::Int64;
                replace::Bool=true)

    select = sample(1:cohort.n, n, replace=replace)
    return cohort[select]
end

function print(cohort::Cohort, option::String="None")
    if option == "None"
        Base.summary(cohort, is_return=false)

    elseif option == "ID"
        print("Individual: [ ")
        for animal in cohort
             print(animal.ID, " ")
        end
        println("]")

    elseif option == "Pedigree"
        return get_pedigree(cohort)
    end
end

function length(cohort::Cohort)
    return length(cohort.animals)
end

function Base.:+(x::Cohort, y::Cohort)
    return Cohort(vcat(x.animals, y.animals))
end

function Base.:+(x::Cohort, y::Animal)
    return Cohort(vcat(x.animals, y))
end

function Base.:+(x::Animal, y::Cohort)
    return Cohort(vcat(x, y.animals))
end

function getindex(cohort::Cohort, I...)
    if length(I...) == 1
        return cohort.animals[1]
    else
        return Cohort(getindex(cohort.animals, I...))
    end
end

Base.setindex!(cohort::Cohort, animal::Animal, i::Int64) =
    Base.setindex!(cohort.animals, animal, i)
Base.show(io::IO, cohort::Cohort) = print(cohort)
Base.iterate(cohort::Cohort, i...) = Base.iterate(cohort.animals, i...)


# function get(cohort::Cohort,
#              item  ::String,
#              option::Any)

#     if item == "Traits"
#         return get_phenotypes(cohort, option)

#     elseif item == "ID"
#         return get_IDs(cohort)

#     elseif item == "Pedigree"
#         return get_pedigree(cohort)

#     elseif item == "DH"
#         return get_DH(cohort, option)

#     else
#         println("""
#             The available options are: 'Triats', 'ID', 'Pedigree', and 'DH'
#         """)
#     end
# end