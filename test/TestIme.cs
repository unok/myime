using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json; 
 
namespace TestIme 
{ 
    class Program 
    { 
        [DllImport("azookey-engine.dll", CallingConvention = CallingConvention.Cdecl)] 
        static extern IntPtr azookey_create(string configJson); 
 
        [DllImport("azookey-engine.dll", CallingConvention = CallingConvention.Cdecl)] 
        static extern void azookey_destroy(IntPtr engine); 
 
        [DllImport("azookey-engine.dll", CallingConvention = CallingConvention.Cdecl)] 
        static extern IntPtr azookey_convert(IntPtr engine, string input); 
 
        [DllImport("azookey-engine.dll", CallingConvention = CallingConvention.Cdecl)] 
        static extern void azookey_free_string(IntPtr str); 
 
        static void Main()
        {
            Console.OutputEncoding = Encoding.UTF8;
            Console.WriteLine("=== MyIme Test Program ===\n"); 
 
            try 
            { 
                // Load configuration 
                string configPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "..", "..", "config.json"); 
                string configJson = File.ReadAllText(configPath); 
                Console.WriteLine("Loaded config.json"); 
 
                // Create engine 
                IntPtr engine = azookey_create(configJson); 
                if (engine == IntPtr.Zero) 
                { 
                    Console.WriteLine("ERROR: Failed to create engine"); 
                    return; 
                } 
                Console.WriteLine("Created AzooKey engine\n"); 
 
                // Test conversions 
                string[] testInputs = { 
                    "konnichiha", 
                    "arigatou", 
                    "ohayougozaimasu", 
                    "sayounara", 
                    "nihongo" 
                }; 
 
                Console.WriteLine("Testing conversions:"); 
                Console.WriteLine("-------------------"); 
 
                foreach (string input in testInputs) 
                { 
                    IntPtr resultPtr = azookey_convert(engine, input); 
                    if (resultPtr != IntPtr.Zero) 
                    { 
                        string result = Marshal.PtrToStringUTF8(resultPtr) ?? "(null)"; 
                        Console.WriteLine($"{input} -> {result}"); 
                        azookey_free_string(resultPtr); 
                    } 
                    else 
                    { 
                        Console.WriteLine($"{input} -> (conversion failed)"); 
                    } 
                } 
 
                // Clean up 
                azookey_destroy(engine); 
                Console.WriteLine("\nEngine destroyed successfully"); 
            } 
            catch (Exception ex) 
            { 
                Console.WriteLine($"ERROR: {ex.Message}"); 
                Console.WriteLine($"Stack trace: {ex.StackTrace}"); 
            } 
 
            Console.WriteLine("\nTest completed."); 
        } 
    } 
} 
