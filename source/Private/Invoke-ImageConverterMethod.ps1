function Invoke-ImageConverterMethod
{
    <#
        .SYNOPSIS
        Calls a .NET constructor or method and returns its exception instead of throwing it.

        .DESCRIPTION
        Runs a constructor (-Type without -Name), a static method (-Type with -Name) or an
        instance method (-InputObject with -Name) in compiled code that catches the exception,
        and returns an object with the properties Result, Exception and Arguments. Exactly one
        of Result and Exception is set; Arguments holds the argument values after the call, so
        out parameters can be read from it. PowerShell records every exception that reaches a
        script in $Error and in the -ErrorVariable of each calling advanced function, also when
        a catch block handles it, so a failure the cmdlets report as one error record would
        otherwise show up twice. The helper class is compiled on first use.

        .PARAMETER Type
        The .NET type whose constructor (without -Name) or static method (with -Name) is called.

        .PARAMETER InputObject
        The object whose instance method is called. Requires the method name in -Name.

        .PARAMETER Name
        The name of the method to call. Without it, the constructor of -Type is called.

        .PARAMETER ArgumentList
        The arguments for the constructor or method, in the order of its parameters. Pass
        $null for an out parameter and read its value from the Arguments property.

        .EXAMPLE
        Invoke-ImageConverterMethod -Type ([System.IO.File]) -Name 'Move' -ArgumentList $tempPath, $targetPath, $true

        Moves the file and returns the exception in the Exception property if the move fails.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Static')]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true, ParameterSetName = 'Static')]
        [System.Type]
        $Type,

        [Parameter(Mandatory = $true, ParameterSetName = 'Instance')]
        [System.Object]
        $InputObject,

        [Parameter(ParameterSetName = 'Static')]
        [Parameter(Mandatory = $true, ParameterSetName = 'Instance')]
        [System.String]
        $Name,

        [Parameter()]
        [AllowEmptyCollection()]
        [AllowNull()]
        [System.Object[]]
        $ArgumentList = @()
    )

    $source = @'
using System;
using System.Management.Automation;
using System.Reflection;

namespace PSImageConverter
{
    public static class SafeInvoker
    {
        // No name: constructor of type; no target: static method of type; otherwise instance method.
        // The argument values are returned after the call, because the binder writes out parameters into them.
        public static Exception Invoke(Type type, object target, string name, object[] arguments, out object result, out object[] argumentValues)
        {
            result = null;
            object[] values = new object[arguments == null ? 0 : arguments.Length];
            for (int index = 0; index < values.Length; index++)
            {
                values[index] = Unwrap(arguments[index]);
            }

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
            PSObject wrapper = value as PSObject;
            return wrapper == null ? value : wrapper.BaseObject;
        }
    }
}
'@
    Add-ImageConverterType -TypeName 'PSImageConverter.SafeInvoker' -TypeDefinition $source

    $target = $null
    if ($PSCmdlet.ParameterSetName -eq 'Instance')
    {
        $target = $InputObject
        $Type = $InputObject.GetType()
    }

    # An unbound -Name arrives as an empty string, which the helper class treats as the constructor.
    $result = $null
    $argumentValues = $null
    $exception = [PSImageConverter.SafeInvoker]::Invoke($Type, $target, $Name, $ArgumentList, [ref] $result, [ref] $argumentValues)

    [PSCustomObject] @{
        Result    = $result
        Exception = $exception
        Arguments = $argumentValues
    }
}
