# Smart_Contract
This is a smart contract for token+presale
# Presale-Lite (Milestone 1)

• Complete ERC20 token contract and presale contract code structure in a Hardhat project.
• Contracts compile successfully with no errors.
• Basic README on how to run the project locally.



- **Token:** `Token.sol` (fixed supply, optional burn via ERC20Burnable)
- **Presale:** `PresaleLite.sol` (flat price, single stage, claim-after toggle)
- **Tooling:** Hardhat + OpenZeppelin

> Scope for **Milestone 1**: code structure, compiles with no errors, basic local run notes.


---

## 1) Requirements 

- Install Node.js 22+ (or 20+)
- npm or yarn
- Git
- Visual Studio Code

## 2) Project Dir  

- Make a Project Dir, named "Token_Presale"
and Open this dir using VS code.
- In that dir, make a file, ".env".

## 3) Install a neccessary modules such as Hardhat
In Terminal of VS Code (Ctrl+Shift + `)
- npm init -y
- npm install --save-dev hardhat@hh2
- npx hardhat init
- Select "Create an empty hardhat.config.js" with your keyboard and hit enter.

## 4) ToKen & Presale smart contract coding
- Making a dir, "contracts" & then make two .sol file.

- TestToken.sol
...
- Presale.sol
...
## 5) ToKen & Presale smart contract coding
- Making a dir, "contracts" & then make two .sol file.

- Token.sol
...
- Presale.sol
...
## 6) ToKen & Presale smart contract compile

- Installing OpenZeppelin contracts module
    npm i @openzeppelin/contracts

- Add the following to the package.json file:
    {
      "scripts": {
      "build": "hardhat compile",
      "clean": "hardhat clean",
      "lint": "echo \"(optional) add solhint/prettier here\" && exit 0"
     }
   }

- Compile two contracts file.
    npx hardhat clean; npx hardhat compile

So, you can see that it was compiled successfully in the terminal.    
Click the image link: Ctrl+ Mouse left click
![alt text](compile_result.png)


