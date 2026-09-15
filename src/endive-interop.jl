using Base.Experimental: @overlay

export Endive
module Endive

using ..WebAssemblyCompiler: @jscall, EndiveRef

## ---- raw "host:hoststream:*" primitives -----------------------
_map_new() = @jscall("host:hoststream:map_new", EndiveRef, Tuple{})
_map_set_i32!(m::EndiveRef, k::EndiveRef, v::Int32) =
@jscall("host:hoststream:map_set_i32", Nothing, Tuple{EndiveRef, EndiveRef, Int32}, m, k, v)
_map_set_f64!(m::EndiveRef, k::EndiveRef, v::Float64) =
@jscall("host:hoststream:map_set_f64", Nothing, Tuple{EndiveRef, EndiveRef, Float64}, m, k, v)
_map_set_bool!(m::EndiveRef, k::EndiveRef, v::Int32) =
@jscall("host:hoststream:map_set_bool", Nothing, Tuple{EndiveRef, EndiveRef, Int32}, m, k, v)

_map_set_ref!(m::EndiveRef, k::EndiveRef, v::EndiveRef) =
@jscall("host:hoststream:map_set_ref", Nothing, Tuple{EndiveRef, EndiveRef, EndiveRef}, m, k, v)

_list_new() = @jscall("host:hoststream:list_new", EndiveRef, Tuple{})
_list_push_i32!(l::EndiveRef, v::Int32) = @jscall("host:hoststream:list_push_i32", Nothing, Tuple{EndiveRef, Int32}, l, v)
_list_push_f64!(l::EndiveRef, v::Float64) = @jscall("host:hoststream:list_push_f64", Nothing, Tuple{EndiveRef, Float64}, l, v)
_list_push_bool!(l::EndiveRef, v::Int32) = @jscall("host:hoststream:list_push_bool", Nothing, Tuple{EndiveRef, Int32}, l, v)
_list_push_ref!(l::EndiveRef, v::EndiveRef) = @jscall("host:hoststream:list_push_ref", Nothing, Tuple{EndiveRef, EndiveRef}, l, v)

release!(h::EndiveRef) = @jscall("host:hoststream:release", Nothing, Tuple{EndiveRef}, h)

_box_i32(v::Int32) = @jscall("host:hoststream:box_i32", EndiveRef, Tuple{Int32}, v)
_box_f64(v::Float64) = @jscall("host:hoststream:box_f64", EndiveRef, Tuple{Float64}, v)
_box_bool(v::Int32) = @jscall("host:hoststream:box_bool", EndiveRef, Tuple{Int32}, v)

## ---- the actual point of this prototype: JS-style incremental strings ----
_box_str_new() = @jscall("host:hoststream:box_str_new", EndiveRef, Tuple{})
_box_str_push!(h::EndiveRef, byte::UInt8) = @jscall("host:hoststream:box_str_push", Nothing, Tuple{EndiveRef, UInt8}, h, byte)
_box_str_finish(h::EndiveRef) = @jscall("host:hoststream:box_str_finish", EndiveRef, Tuple{EndiveRef}, h)

function boxstr(s::String)
    bytes = unsafe_wrap(Vector{UInt8}, s)
    h = _box_str_new()
    for (i, b) in enumerate(bytes)
        _box_str_push!(h, b)
    end
    _box_str_finish(h)
end

## ---- public map/list API (same shape as HOST) ------------------------
"""
    HOSTStream.mapnew() -> EndiveRef
"""
mapnew() = _map_new()

function mapset!(m::EndiveRef, k::String, v::String)
    kh = boxstr(k)
    vh = boxstr(v)
    _map_set_ref!(m, kh, vh)
    nothing
end
function mapset!(m::EndiveRef, k::String, v::Int32)
    kh = boxstr(k)
    _map_set_i32!(m, kh, v)
    nothing
end
function mapset!(m::EndiveRef, k::String, v::Float64)
    kh = boxstr(k)
    _map_set_f64!(m, kh, v)
    nothing
end
function mapset!(m::EndiveRef, k::String, v::Bool)
    kh = boxstr(k)
    _map_set_bool!(m, kh, v ? Int32(1) : Int32(0))  ## avoid Int32(::Bool), see HOST's identical note
    nothing
end
function mapset!(m::EndiveRef, k::String, v::EndiveRef)
    kh = boxstr(k)
    _map_set_ref!(m, kh, v)
    nothing
end
mapset!(m::EndiveRef, k::String, v::Integer) = mapset!(m, k, Int32(v))
mapset!(m::EndiveRef, k::String, v::Float32) = mapset!(m, k, Float64(v))

listnew() = _list_new()

function listpush!(l::EndiveRef, v::String)
    vh = boxstr(v)
    _list_push_ref!(l, vh)
    nothing
end
listpush!(l::EndiveRef, v::Int32) = (_list_push_i32!(l, v); nothing)
listpush!(l::EndiveRef, v::Float64) = (_list_push_f64!(l, v); nothing)
listpush!(l::EndiveRef, v::Bool) = (_list_push_bool!(l, v ? Int32(1) : Int32(0)); nothing)
listpush!(l::EndiveRef, v::EndiveRef) = (_list_push_ref!(l, v); nothing)
listpush!(l::EndiveRef, v::Integer) = listpush!(l, Int32(v))
listpush!(l::EndiveRef, v::Float32) = listpush!(l, Float64(v))

function object(v::Vector{Float64})
    l = listnew()
    n = length(v)
    for i in 1:n
        listpush!(l, v[i])
    end
    return l
end

function object(v::Vector{Int32})
    l = listnew()
    n = length(v)
    for i in 1:n
        listpush!(l, v[i])
    end
    return l
end

function object(v::AbstractVector)
    l = listnew()
    for x in v
        listpush!(l, object(x))
    end
    return l
end

@inline @generated function object(nt::NamedTuple)
    ks = fieldnames(nt)
    res = Expr(:block)
    push!(res.args, :(m = mapnew()))
    for k in ks
        sk = String(k)
        qk = QuoteNode(k)
        push!(res.args, :(mapset!(m, $sk, object(getfield(nt, $qk)))))
    end
    push!(res.args, :(return m))
    return res
end

function object(tpl::Tuple)
    l = listnew()
    _objectpush!(l, tpl...)
    return l
end
@inline _objectpush!(l) = nothing
@inline _objectpush!(l, x, xs...) = (listpush!(l, object(x)); _objectpush!(l, xs...))

object(x::EndiveRef) = x
object(x::Int32) = _box_i32(x)
object(x::Float64) = _box_f64(x)
object(x::Bool) = _box_bool(x ? Int32(1) : Int32(0))
object(s::String) = boxstr(s)
object(x::Integer) = object(Int32(x))
object(x::Float32) = object(Float64(x))

end # module Endive
_convert(::Type{EndiveRef}, x) = Endive.object(x)
