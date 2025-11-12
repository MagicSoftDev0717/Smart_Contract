# Smart_Contract For Token+Presale
This is a smart contract for token+presale
# Initial (Milestone 1)

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


////////////////////////////////////////////////////////////////
# Test in Sepolia (Milestone 2)

1) Contracts Depoly
In terminal...
    npm i dotenv
    npm i -D @nomicfoundation/hardhat-toolbox

In .env file
    - SEPOLIA_RPC_URL : 
    - ETHERSCAN_API_KEY : In https://etherscan.io/apidashboard, "+ Add" button click
    - Enter the Private Key of your TREASURY address into the PRIVATE_KEY and OWNER macro variables.   

To get mock USDT_SEPOLIA and ORACLE_ETH_USD address
    npx hardhat run scripts/deploy-mock-usdt.js --network sepolia
    npx hardhat run scripts/deploy-mock-oracle.js --network sepolia

In terminal...

    n   px hardhat run scripts/deploy.js --network sepolia   # I thiink you can see the deploy result in terminal.

fund
        npx hardhat run scripts/fund.js --network sepolia 

buyEth
        npm remove solc
        npm add solc@0.8.7-fixed

        ////////////////////
        npx hardhat run scripts/buyEth.js --network sepolia   

buyUsdt

        npx hardhat run scripts/buyUsdt.js --network sepolia    

pauseStage - This script is your stage management control tool for the presale contract.

        node scripts/pauseStage.js 0 pause

manualAdvance - This script is your stage-transition controller for the presale contract.

    ???   

enableClaim - It’s designed so that the owner wallet can toggle whether buyers are allowed to claim tokens after the presale ends.

            npx hardhat run scripts/enableClaim.js --network sepolia
            or
            node scripts/claim.js on
            node scripts/claim.js off


claim - This script is your stage-transition controller for the presale contract.

            npx hardhat run scripts/claim.js --network sepolia
            or
            node scripts/claim.js

checkBalance - It checks the ETH and token balances of the presale contract on-chain — essential for validating fund flow and ensuring 
                that tokens are properly loaded for claims or liquidity lock.

            npx hardhat run scripts/checkBalance.js --network sepolia
            or
            node scripts/checkBalance.js

checkStats - This script is your “at-a-glance health dashboard” for the presale. It pulls global totals and per-stage numbers straight from the contract so you 
                (and the client) can sanity-check that on-chain sums line up with expectations.

            npx hardhat run scripts/checkStats.js --network sepolia
            or
            node scripts/checkStats.js

checkStages - This script is your stage inspector. It fetches the presale’s stage list, prints each stage’s config and progress, and then shows overall totals. 
              This is perfect for the client to confirm timing windows, prices, caps, and progress per stage.

            npx hardhat run scripts/checkStats.js --network sepolia
            or
            node scripts/checkStats.js

verifyContracts - this script is your “one-button Etherscan verifier.” It shells out to Hardhat’s verify task and is meant to verify both the token and the presale

            npx hardhat run scripts/checkStats.js --network sepolia
            or
            node scripts/verifyContracts.js

