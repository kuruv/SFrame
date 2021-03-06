'''
Copyright (C) 2016 Turi
All rights reserved.

This software may be modified and distributed under the terms
of the BSD license. See the LICENSE file for details.
'''
from .cy_ipc cimport PyCommClient

from .cy_variant cimport variant_type
from .cy_variant cimport from_dict as variant_map_from_dict
from .cy_variant cimport to_dict as variant_map_to_dict
from .cy_variant cimport from_value as variant_from_value
from .cy_variant cimport make_shared_variant

from .cy_flexible_type cimport pylist_from_flex_list
from .cy_flexible_type cimport flex_list_from_iterable
from .cy_flexible_type cimport pyobject_from_flexible_type
from .cy_flexible_type cimport flexible_type_from_pyobject
from .cy_flexible_type cimport pydict_from_gl_options_map

from . cimport cy_graph
from . cimport cy_sarray
from . cimport cy_sframe

from .cy_sarray cimport UnitySArrayProxy
from .cy_model cimport UnityModel, create_model_from_proxy

from libcpp.vector cimport vector
from libcpp.string cimport string
from libcpp.map cimport map

from .cy_cpp_utils cimport str_to_cpp, cpp_to_str, from_vector_of_strings, disable_cpp_str_decode, enable_cpp_str_decode

from cython.operator cimport dereference as deref
import inspect
from ..util import cloudpickle
import pickle


cdef class UnityGlobalProxy:
    def __cinit__(self, PyCommClient cli):
        assert cli, "CommClient is Null"
        self.thisptr = new unity_global_proxy(deref(cli.thisptr))
        self._base_ptr.reset(<unity_global_base*>(self.thisptr))
        self._cli = cli

    cpdef get_metric_server_port(self):
        return self.thisptr.get_metric_server_port()

    cpdef get_version(self):
        return cpp_to_str(self.thisptr.get_version())

    cpdef get_graph_dag(self):
        return cpp_to_str(self.thisptr.get_graph_dag())

    cpdef load_graph(self, _fname):
        cdef string fname = str_to_cpp(_fname)
        cdef unity_sgraph_base_ptr g
        with nogil:
            g = self.thisptr.load_graph(fname)
        return cy_graph.create_proxy_wrapper_from_existing_proxy(self._cli, g)

    cpdef list_toolkit_functions(self):
        return from_vector_of_strings(self.thisptr.list_toolkit_functions())

    cpdef list_toolkit_classes(self):
        return from_vector_of_strings(self.thisptr.list_toolkit_classes())

    cpdef describe_toolkit_function(self, fname):
        return pydict_from_gl_options_map(
            self.thisptr.describe_toolkit_function(str_to_cpp(fname)))

    cpdef describe_toolkit_class(self, model):
        return pydict_from_gl_options_map(self.thisptr.describe_toolkit_class(str_to_cpp(model)))

    cpdef create_toolkit_class(self, classname):
        return create_model_from_proxy(
            self._cli, self.thisptr.create_toolkit_class(str_to_cpp(classname)))

    cpdef run_toolkit(self, _toolkit_name, object arguments):
        cdef string toolkit_name = str_to_cpp(_toolkit_name)
        cdef variant_map_type options = variant_map_from_dict(arguments)
        cdef toolkit_function_response_type response
        with nogil:
            response = self.thisptr.run_toolkit(toolkit_name, options)
        return (response.success, cpp_to_str(response.message),
                variant_map_to_dict(self._cli, response.params))

    cpdef save_model(self, model, _url, explicit_model_wrapper = None):
        cdef string url = str_to_cpp(_url) 
        proxy = model.__proxy__
        cdef model_base_ptr m = ((<UnityModel?>(proxy))._base_ptr)
        if not explicit_model_wrapper:
            model_wrapper = model._get_wrapper()
        else:
            model_wrapper = explicit_model_wrapper
        if not inspect.isfunction(model_wrapper):
            raise ValueError("Model wrapper must be a function: UnityModel->Model")
        # Temporarily remove __proxy__ because cloudpickle hates it.
        model.__proxy__ = None
        cdef string model_dump = str_to_cpp(cloudpickle.dumps(model_wrapper))
        model.__proxy__ = proxy
        with nogil:
            self.thisptr.save_model(m, model_dump, url)

    cpdef load_model(self, _url):
        cdef string url = str_to_cpp(_url) 
        cdef variant_map_type response
        with nogil:
            response = self.thisptr.load_model(url)

        try:
            disable_cpp_str_decode()
            variant_dict = variant_map_to_dict(self._cli, response)
        finally:
             enable_cpp_str_decode()

        model_wrapper = pickle.loads(variant_dict[b'model_wrapper'])
        return model_wrapper(variant_dict[b'model_base'])

    cpdef eval_lambda(self, object fn, object arg):
        assert inspect.isfunction(fn), "First argument must be a function"
        from .. import util
        cdef string lambda_str = str_to_cpp(util._pickle_to_temp_location_or_memory(fn))
        cdef flexible_type flex_val = flexible_type_from_pyobject(arg)
        cdef flexible_type ret = self.thisptr.eval_lambda(lambda_str, flex_val)
        return pyobject_from_flexible_type(ret)

    cpdef eval_dict_lambda(self, object fn, object arg):
        assert inspect.isfunction(fn), "First argument must be a function"
        from .. import util
        cdef string lambda_str = str_to_cpp(util._pickle_to_temp_location_or_memory(fn))
        cdef vector[string] keys = arg.keys()
        cdef flex_list values = flex_list_from_iterable([arg[k] for k in arg])
        cdef flexible_type ret = self.thisptr.eval_dict_lambda(lambda_str, keys, values)
        return pyobject_from_flexible_type(ret)

    cpdef parallel_eval_lambda(self, object fn, object argument_list):
        assert inspect.isfunction(fn), "First argument must be a function"
        from .. import util
        cdef string lambda_str = str_to_cpp(util._pickle_to_temp_location_or_memory(fn))
        cdef vector[flexible_type] flex_vec = flex_list_from_iterable(argument_list)
        cdef vector[flexible_type] ret = self.thisptr.parallel_eval_lambda(lambda_str, flex_vec)
        return pylist_from_flex_list(ret)

    cpdef clear_metrics_server(self):
        self.thisptr.clear_metrics_server()

    cpdef __read__(self, object url):
        return cpp_to_str(self.thisptr.__read__(str_to_cpp(url)))

    cpdef __write__(self, object url, object content):
        self.thisptr.__write__(str_to_cpp(url), str_to_cpp(content))

    cpdef __mkdir__(self, object url):
        return self.thisptr.__mkdir__(str_to_cpp(url))

    cpdef __chmod__(self, object url, short mode):
        return self.thisptr.__chmod__(str_to_cpp(url), mode)

    cpdef __get_heap_size__(self):
        return self.thisptr.__get_heap_size__()

    cpdef __get_allocated_size__(self):
        return self.thisptr.__get_allocated_size__()

    cpdef list_globals(self, bint runtime_modifiable):
        return pydict_from_gl_options_map(self.thisptr.list_globals(runtime_modifiable))

    cpdef set_global(self, key, object value):
        return cpp_to_str(self.thisptr.set_global(str_to_cpp(key),
                                                  flexible_type_from_pyobject(value)))

    cpdef create_sequential_sarray(self, ssize_t size, ssize_t start, bint reverse):
        cdef unity_sarray_base_ptr proxy
        with nogil:
            proxy = self.thisptr.create_sequential_sarray(size, start, reverse)
        return cy_sarray.create_proxy_wrapper_from_existing_proxy(self._cli, proxy)

    cpdef get_current_cache_file_location(self):
        cdef string loc = b""
        with nogil:
            loc = self.thisptr.get_current_cache_file_location()
        return cpp_to_str(loc)

    cpdef load_toolkit(self, soname, module_subpath):
        return self.thisptr.load_toolkit(str_to_cpp(soname), str_to_cpp(module_subpath))

    cpdef list_toolkit_functions_in_dynamic_module(self, soname):
        return from_vector_of_strings(
                self.thisptr.list_toolkit_functions_in_dynamic_module(str_to_cpp(soname)))

    cpdef list_toolkit_classes_in_dynamic_module(self, soname):
        return from_vector_of_strings(
            self.thisptr.list_toolkit_classes_in_dynamic_module(str_to_cpp(soname)))

    cpdef get_graphlab_object_type(self, uri):
        return cpp_to_str(self.thisptr.get_graphlab_object_type(str_to_cpp(uri)))

cdef bint is_function_closure_info(object closure) except *:
    try:
        return ("native_fn_name" in closure.__dict__) and ("arguments" in closure.__dict__)
    except:
        return False

cdef function_closure_info make_function_closure_info(object closure) except *:
    cdef function_closure_info ret
    ret.native_fn_name  = str_to_cpp(closure.native_fn_name)
    ret.arguments.resize(len(closure.arguments))
    for i in range(len(closure.arguments)):
        ret.arguments[i].first = closure.arguments[i][0]
        val = variant_from_value(closure.arguments[i][1])
        ret.arguments[i].second = make_shared_variant(val)
    return ret
