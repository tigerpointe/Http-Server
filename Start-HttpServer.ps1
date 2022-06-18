<#

.SYNOPSIS
This script implements a simple HTTP server in PowerShell.

.DESCRIPTION
An HTTP Listener is used to monitor port traffic.  Asynchronous versions
of the methods were chosen so that termination signals (such as Ctrl+C)
could be successfully caught and used to stop the main processing loop
at regular intervals, while still behaving like a blocking listener.

Once an HTTP connection has been established, the requested URL path is
examined and the file system is searched for a corresponding document.  If
found, the specified document content is returned with a status code of
200 (Success).  Otherwise, a status code of 404 (Not Found) is returned.
Exceptions always return a status code of 500 (Internal Server Error).

This script will return any static text or image file, which includes CSS
and JavaScript for dynamic client content.  Dynamic server features (such
as query string parameters and form fields) are logged but never used.
These code blocks could be modified to call external handlers for
generating dynamic documents.

.PARAMETER root
Specifies the root folder of the web site.  If not specified, the script
folder will be selected.  A drive name is mapped to the web site root to
prevent relative external paths from being accessed (ex. "../../Windows").

.PARAMETER prefix
Specifies the URI prefix that is compared to the incoming request.  Any
port can be monitored, but special numbered ports (like port 80 or 443)
require that the script be started with "Run as administrator" privileges.
The prefix value must be terminated with a trailing forward slash.

.PARAMETER default
Specifies the default document to return for the root path.

.PARAMETER verbose
Enables the use of verbose log messages.

.INPUTS
None.

.OUTPUTS
System.String
A status log of all requests.

.EXAMPLE
Start-HttpServer.ps1
Starts the HTTP server with the default options.

.EXAMPLE
Start-HttpServer.ps1 -root "C:\Inetpub\wwwroot"
Starts the HTTP server with an alternate root folder.

.EXAMPLE
Start-HttpServer.ps1 -prefix "http://+:80/"
Starts the HTTP server with an alternate prefix for binding to all hosts.
Binding to "all hosts" requires "Run as administrator" privileges.
Binding to port 80 requires "Run as administrator" privileges.
This example shows how documents can be served to others on your network.

.EXAMPLE
Start-HttpServer.ps1 -default "Default.htm"
Starts the HTTP server with an alternate default document.

.EXAMPLE
Start-HttpServer.ps1 -verbose > output.log
Starts the HTTP server with maximum verbosity redirected into a log file.

.NOTES
The following shell commands can be used to bind and unbind TLS/SSL
certificates on a port:

  netsh http add sslcert ipport=0.0.0.0:443 `
                         certhash=0000000000003ed9cd0c315bbb6dc1c08da5e6 `
                         appid={00112233-4455-6677-8899-AABBCCDDEEFF} `
                         clientcertnegotiation=enable
  netsh http delete sslcert ipport=0.0.0.0:443

HTTP server features related to personally identifiable information (PII)
such as authentication schemes and cookies have not been implemented.
Please see HttpListener.AuthenticationSchemes, HttpListenerRequest.Cookies
and HttpListenerResponse.Cookies for implementation considerations.

MIT License

Copyright (c) 2022 TigerPointe Software, LLC

Permission is hereby granted, free of charge, to any person obtaining a
copy of this software and associated documentation files (the "Software"),
to deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.

If you find this script helpful, please do something kind for free.

History:
01.00 2022-Jun-12 Scott Initial release.

.LINK
https://docs.microsoft.com/en-us/dotnet/api/system.net.httplistener?view=net-6.0

.LINK
https://docs.microsoft.com/en-us/dotnet/framework/wcf/feature-details/how-to-configure-a-port-with-an-ssl-certificate

#>

param
(

    # Defines the site root folder (defaults to the script folder)
    [string] $root = $PSScriptRoot

    # Defines the listener prefix (protocol://hostNameOrIpAddress:portNumber)
  , [string] $prefix = "http://localhost:8080/"

    # Defines the default document (index.html, Default.htm, etc.)
  , [string] $default = "index.html"

    # Enables verbose log messages
  , [switch] $verbose

)

# Add the additional required assemblies
Add-Type -AssemblyName System.Web;

# Assign the web root drive (cannot be escaped using "../" paths)
$drive = New-PSDrive -Name       "wwwroot" `
                     -PSProvider "FileSystem" `
                     -Root       $root;
Write-Host "Root    $root";
Write-Host "Prefix  $prefix";
Write-Host "Default $default";

# Create the listener
$context  = $null;
$listener = New-Object -TypeName System.Net.HttpListener;
try
{

  # Start the listener
  $listener.Prefixes.Add($prefix);
  $listener.Start();
  Write-Host "Started (Press Ctrl+C to Stop)";
  while ($listener.IsListening)
  {

    # Create a new string builder for the status log message
    $message = New-Object System.Text.StringBuilder;

    # Get the request (async methods wait for 500ms and then repeat, allowing
    # any blocked Ctrl+C signals to be processed after each iteration)
    $async = $listener.GetContextAsync();
    while (-not $async.AsyncWaitHandle.WaitOne(500)) { }
    $context = $async.GetAwaiter().GetResult();
    $request = $context.Request;
    $method  = $request.HttpMethod;
    $url     = $request.Url.LocalPath;
    [void]$message.Append("$method $url");

    # Check for the query string parameters
    $spacer = " ";
    $params = $request.QueryString;
    foreach ($param in $params)
    {
      [void]$message.Append("$spacer$param=$($params[$param])");
      $spacer = "&";
    }

    # Check for a request body (ex. posted form fields)
    $body = $null;
    if ($request.HasEntityBody)
    {
      $reader = New-Object -TypeName System.IO.StreamReader `
                           -ArgumentList $request.InputStream;
      $body   = $reader.ReadToEnd();
      [void]$message.Append(" $body");
      $reader.Dispose();
    }

    # Check for the request headers (verbose only)
    $headers = $request.Headers;
    if ($verbose.IsPresent)
    {
      foreach ($header in $headers)
      {
        [void]$message.Append("`n  [$header]`n    $($headers[$header])");
      }
    }

    # Get the requested document content as a byte array [System.Byte[]]
    $content = $null;
    if ($url.EndsWith("/")) { $url = "$url$default"; } # Default document
    if (Test-Path -Path "wwwroot:$url")
    {

      # Use "-Encoding Byte" for PS<=5.1 or "-AsByteStream" for PS>=6.0
      $content = Get-Content -Path "wwwroot:$url" `
                             -Raw -Encoding Byte;

    }

    # Send the response
    $response = $context.Response;
    if ($content -eq $null)
    {
      $response.StatusCode = 404; # Not Found
    }
    else
    {
      $response.StatusCode = 200; # Success
      $response.ContentType = `
        [System.Web.MimeMapping]::GetMimeMapping("wwwroot:$url");
      $response.ContentLength64 = $content.Length;
      $response.OutputStream.Write($content, 0, $content.Length);
      $response.OutputStream.Flush();
    }
    [void]$message.Insert(0, "$($response.StatusCode) ");
    $response.Close();

    # Write the status log message
    $now = Get-Date -Format "yyyy-MMM-dd HH:mm:ss";
    [void]$message.Insert(0, "$now ");
    Write-Output $message.ToString();

  }

}
catch
{

  # Handle the exception
  if ($context -ne $null)
  {
    $context.Response.StatusCode = 500; # Internal Server Error
    $context.Response.Close();
  }
  Write-Host "Error   $_";

}
finally
{

  # Stop the listener (ex. Ctrl+C)
  $listener.Stop();
  Write-Host "Stopped";

  # Remove the web root drive
  Remove-PSDrive -Name "wwwroot";

}