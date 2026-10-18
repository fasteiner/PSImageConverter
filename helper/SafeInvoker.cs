using System;
using System.Reflection;

namespace PSImageConverter
{
    /// <summary>
    /// Calls a constructor or method and returns its exception instead of throwing it.
    /// </summary>
    /// <remarks>
    /// PowerShell records every exception that reaches a script in $Error and in the -ErrorVariable of
    /// each calling advanced function, also when a catch block handles it. The module reports a failure
    /// as one error record, so .NET calls that can fail go through this class (Invoke-ImageConverterMethod).
    /// </remarks>
    public static class SafeInvoker
    {
        // Resolved by name, so the assembly needs no reference to System.Management.Automation (a NuGet package).
        private static readonly Type PSObjectType = Type.GetType("System.Management.Automation.PSObject, System.Management.Automation", false);
        private static readonly PropertyInfo BaseObjectProperty = PSObjectType == null ? null : PSObjectType.GetProperty("BaseObject");

        /// <summary>
        /// Calls the constructor of <paramref name="type"/> (no <paramref name="name"/>), a static method
        /// (no <paramref name="target"/>) or an instance method of <paramref name="target"/>.
        /// </summary>
        /// <param name="type">The type whose constructor or method is called.</param>
        /// <param name="target">The object whose instance method is called, or null for a constructor or static method.</param>
        /// <param name="name">The method name, or null or empty for the constructor.</param>
        /// <param name="arguments">The arguments in the order of the parameters; PowerShell wrappers (PSObject) are removed.</param>
        /// <param name="result">The return value of the call, or null when it failed.</param>
        /// <param name="argumentValues">The argument values after the call, which hold the values of out parameters.</param>
        /// <returns>The exception the call raised (the inner exception of a TargetInvocationException), or null when it succeeded.</returns>
        public static Exception Invoke(Type type, object target, string name, object[] arguments, out object result, out object[] argumentValues)
        {
            result = null;
            object[] values = new object[arguments == null ? 0 : arguments.Length];
            for (int index = 0; index < values.Length; index++)
            {
                values[index] = Unwrap(arguments[index]);
            }

            // The binder writes out parameters into this array.
            argumentValues = values;

            try
            {
                if (string.IsNullOrEmpty(name))
                {
                    result = Activator.CreateInstance(type, values);
                }
                else
                {
                    BindingFlags flags = BindingFlags.Public | BindingFlags.InvokeMethod | (target == null ? BindingFlags.Static : BindingFlags.Instance);
                    result = type.InvokeMember(name, flags, null, Unwrap(target), values);
                }

                return null;
            }
            catch (TargetInvocationException exception) when (exception.InnerException != null)
            {
                return exception.InnerException;
            }
            catch (Exception exception)
            {
                return exception;
            }
        }

        private static object Unwrap(object value)
        {
            if (value != null && BaseObjectProperty != null && PSObjectType.IsInstanceOfType(value))
            {
                return BaseObjectProperty.GetValue(value);
            }

            return value;
        }
    }
}
