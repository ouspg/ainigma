#include <iostream>
#include <fstream>
#include <string>
#include <algorithm>

#ifndef MY_SECRET_KEY
#define MY_SECRET_KEY "c91d58581f2e65410bdf13adea111892"
#endif


/// PURPOSE: Converts the encryption key from hexadecimal format into its byte representation.
/// PARAMS:
///    - key: A string representing the encryption key in hexadecimal format.
/// RETURNS: String where each pair of hexadecimal characters from the encryption key
///          is converted into a corresponding byte.
std::string function_A(const std::string& key) {
    //[DEBUG] std::cout << "function_A: received encryption key " << key << std::endl;
    std::string output;
    for (size_t i = 0; i < key.length(); i += 2) {
        std::string byteStr = key.substr(i, 2);
        char byte = static_cast<char>(std::stoi(byteStr, nullptr, 16));
        output.push_back(byte);
    }
    //[DEBUG] std::cout << "function_A: processed encryption key " << output << std::endl;
    return output;
}

/// PURPOSE: Encrypts the flag using the processed encryption key with a bitwise XOR operation.
/// PARAMS:
///    - flag: The string (flag) to be encrypted.
///    - processedKey: The encryption key that has been processed into bytes by function_A.
/// RETURNS: A string where each character of the flag has been XOR-ed with the corresponding
///          character of the processed encryption key. Resulting in the encrypted flag.
std::string function_B(const std::string& flag, const std::string& processedKey) {
    //[DEBUG] std::cout << "function_B received flag " << flag << std::endl;
    //[DEBUG] std::cout << "function_B received processedKey " << processedKey << std::endl;

    std::string output;
    for (size_t i = 0; i < flag.size(); ++i) {
        char encodedChar = flag[i] ^ processedKey[i % processedKey.size()];
        output.push_back(encodedChar);
    }

    //[DEBUG] std::cout << "function_B encrypted flag " << output << std::endl;
    return output;
}

/// PURPOSE: Reads the flag from the command-line arguments, processes the encryption key, encrypts
///          the flag using the processed key, and writes the resulting encrypted flag to "encrypted_output.txt".
/// PARAMS:
///    - argc: Number of command-line args.
///    - argv: An array of command-line args where argv[1] is the flag.
/// RETURNS: Returns 0 if program ran successfully, 1 if there was an error.
int main(int argc, char* argv[]) {
    if (argc != 2) {
        std::cerr << "Usage: " << argv[0] << " <flag>" << std::endl;
        return 1;
    }
    // std::string encryptionKey = "d25ab2cc06233e7a3a276afe4215df66"; // can change but keep even number of characters
    std::string encryptionKey = MY_SECRET_KEY;

    std::string flag = argv[1];
    // [DEBUG] std::cout << "original flag " << flag << std::endl;

    char* outputDir = std::getenv("OUTPUT_DIR");
    if (outputDir == nullptr) {
        outputDir = (char*)".";
    }
    std::string outputFileName = std::string(outputDir) + "/encrypted_output.txt";
    // std::cout << "original key " << encryptionKey << std::endl;

    std::reverse(encryptionKey.begin(), encryptionKey.end()); // reverse the key to add an extra reversing step
    std::string processedKey = function_A(encryptionKey);
    std::string encryptedFlag = function_B(flag, processedKey);

    std::ofstream outputFile(outputFileName);
    if (!outputFile.is_open()) {
        std::cerr << "Error opening output file." << std::endl;
        return 1;
    }

    outputFile << encryptedFlag;
    outputFile.close();

    //[DEBUG] std::cout << "Encrypted flag written to " << outputFileName << std::endl;

    return 0;
}
