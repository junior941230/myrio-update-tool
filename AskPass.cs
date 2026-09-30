using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;

internal static class AskPass
{
    private static int Main(string[] args)
    {
        if (args.Length == 0 || args[0].IndexOf("password", StringComparison.OrdinalIgnoreCase) < 0)
            return 1;

        try
        {
            string path = Environment.GetEnvironmentVariable("MYRIO_PASSWORD_FILE");
            if (String.IsNullOrEmpty(path))
                return 1;

            byte[] encrypted = Convert.FromBase64String(File.ReadAllText(path).Trim());
            byte[] plain = ProtectedData.Unprotect(encrypted, null, DataProtectionScope.CurrentUser);
            try
            {
                Console.OutputEncoding = new UTF8Encoding(false);
                Console.WriteLine(Encoding.UTF8.GetString(plain));
                return 0;
            }
            finally
            {
                Array.Clear(plain, 0, plain.Length);
            }
        }
        catch
        {
            return 1;
        }
    }
}
