# -----------------------------------------------------------
#
# Constructing the matrix elements of the derivative
# operator in the 1-D DG Basis
#
# -----------------------------------------------------------

# Efficiency criticality: LOW
# Computations only performed once

# Accuracy criticality: HIGH
# Critical for accurate PDE evolution


# -----------------------------------------------------
# 1-D Derivatives
# -----------------------------------------------------

function dLegendreP(k,x)
    k<=K_max || throw(DomainError())
    return array2poly(symbolic_diff(leg_coeffs[k+1]),x)
end


function dh(k,mode,x)
    mode<=k || throw(DomainError())
    return array2poly(symbolic_diff((@view dg_coeffs[k][:,mode])),x)
end

function dleg(mode::Int, x::T) where T <: Real
    return sqrt(2.0)*dLegendreP(mode-1, 2*x-1) *2
end

function dbasis(level::Int, cell::Int, mode::Int, x::T) where T <: Real
    return dleg(mode, (1<<level)*x - (cell-1)) * (2.0)^(level/2) * (1<<level)
end

function dbasis(level::Int, cell::Int, mode::Int)
    return x->dbasis(level, cell, mode, x)
end

# -----------------------------------------------------
# Shifted and scaled derivatives: v
# -----------------------------------------------------

function dv(k::Int, level::Int, cell::Int, mode::Int, x::Real)
    if level==0 # At the base level, we are not discontinuous, and we simply
                # use Legendre polynomials up to degree k-1 as a basis
        return 2*dLegendreP(mode-1,2*x-1)*sqrt(2.0)
    else
        return (1<<(level))*dh(k, mode, (1<<level)*x - (2*cell-1)) * (2.0)^(level/2)
        # Otherwise we use an appropriately shifted, scaled, and normalized
        # DG function
    end
end

function dv(k::Int, level::Int, cell::Int, mode::Int)
    return (xs::Real -> dv(k,level,cell,mode,xs))
end


# -----------------------------------------------------
# Numerical Inner Product
# -----------------------------------------------------

# TODO: There is a way to do this all symbolically, with no use for numerics
function inner_product1D(f::Function, g::Function, lvl::Int, cell::Int;
                                rtol = REL_TOL, atol = ABS_TOL, maxevals=MAX_EVALS)
    xmin = (cell-1)/(1<<max(0, lvl-1))
    xmax = (cell)/(1<<max(0, lvl-1))
    h = (x-> f(x)*g(x))
    (val, err) = hquadrature(h, xmin, xmax; rtol=rtol, atol=atol, maxevals=maxevals)
    return val
end

# -----------------------------------------------------
# Taking Derivative of Array Representing Polynomial
# -----------------------------------------------------

function symbolic_diff(v::AbstractArray{T}) where T <: Real
    n=length(v)
    k=div(n,2)
    ans = zeros(T,n)
    for i in 1:n
        if i<k
            ans[i] = i*v[i+1]
        elseif i > k && i<2k
            ans[i] = (i-k) * v[i+1]
        else
            ans[i]=0
        end
    end
    return ans
end

# -----------------------------------------------------
# < f_1 | D | f_2 > matrix elements
# -----------------------------------------------------

# Matrix element of legendre basis on [-1, 1]
function legendreDlegendre(mode1::Int, mode2::Int)
    return inner_product(leg_coeffs[mode1], symbolic_diff(leg_coeffs[mode2]))
end

# Matrix element of position basis elements
function legvDv(level, cell1, mode1, cell2, mode2;
                rtol = REL_TOL, atol=ABS_TOL, maxevals=MAX_EVALS)
    if cell1 == cell2
        return (1<<(level+1))*legendreDlegendre(mode1, mode2)
    end
    return 0.0
end

# Matrix element of DG basis on [-1, 1]
function hDh(k::Int, mode1::Int, mode2::Int)
    return inner_product((@view dg_coeffs[k][:,mode1]),
                         symbolic_diff((@view dg_coeffs[k][:,mode2])))
end

# Matrix element of hierarchical basis elements
function vDv(k::Int, lvl1::Int, cell1::Int, mode1::Int, lvl2::Int, cell2::Int, mode2::Int;
                    rtol = REL_TOL, atol = ABS_TOL, maxevals=MAX_EVALS)
    if lvl1 == lvl2
        if lvl1 == 0
            return 2*legendreDlegendre(mode1, mode2)
        end
        if cell1 == cell2
            return hDh(k, mode1, mode2)*(1<<max(0, lvl1))
        end
        return 0.0
    end
    if lvl1 < lvl2
        if lvl1 == 0
            return inner_product1D(v(k,0,1,mode1), dv(k,lvl2,cell2,mode2), lvl2, cell2;
                                    rtol = rtol, atol = atol, maxevals=maxevals)
        end
        if (1<<(lvl2-lvl1))*cell1 >= cell2 && (1<<(lvl2-lvl1))*(cell1-1) < cell2
            return inner_product1D(v(k,lvl1,cell1,mode1), dv(k,lvl2,cell2,mode2), lvl2, cell2;
                                    rtol = rtol, atol = atol, maxevals=maxevals)
        end
        return 0.0
    end
    return 0.0

end

# -----------------------------------------------------
# < f_1 | D | f_2 > for a specific f_2 over all f_1
# -----------------------------------------------------

function diff_basis_DG(k::Int, level::Int, cell::Int, mode::Int)
    dcoeffs = Array{Float64}(undef, level+1, k)
    p = cell
    for l in level:-1:0
        for f_n in 1:k
            dcoeffs[l+1,f_n] = vDv(k, l, p, f_n, level, cell, mode)
        end
        p = ceil(Int, p/2)
    end
    return dcoeffs
end
