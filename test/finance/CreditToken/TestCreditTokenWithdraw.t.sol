pragma solidity >=0.6.0;

import "truffle/Assert.sol";
import "./Base.t.sol";

contract TestCreditTokenWithdraw is Base {

    function testRequestWithdrawWithSufficientFunds() public {
        
        issuer.issueTokens(address(alpha), 100 finney);
        alpha.transfer(address(beta), 20 finney);

        addErc20Stock(1 ether);
        
        beta.requestWithdraw();
        Assert.equal(creditToken.balanceOf(address(beta)), 10 finney, "beta credit");
        Assert.equal(erc20.balanceOf(address(beta)), 10 finney, "beta balance");

        alpha.requestWithdraw();
        Assert.equal(creditToken.balanceOf(address(alpha)), 60 finney, "alpha credit");
        Assert.equal(erc20.balanceOf(address(alpha)), 20 finney, "alpha balance");
        
        Assert.equal(creditProvider.totalTokenStock(), 970 finney, "token stock");
    }

    function testRequestWithdrawWithoutFunds() public {
        
        issuer.issueTokens(address(alpha), 100 finney);
        alpha.transfer(address(beta), 20 finney);

        (bool success1, ) = address(alpha).call(abi.encodeWithSelector(
                bytes4(keccak256("requestWithdraw()"))));
        (bool success2, ) = address(beta).call(abi.encodeWithSelector(
                bytes4(keccak256("requestWithdraw()"))));

        Assert.equal(success1, false, "alpha cant withdraw");
        Assert.equal(success2, false, "beta cant withdraw");

        Assert.equal(creditToken.balanceOf(address(alpha)), 80 finney, "alpha credit");
        Assert.equal(creditToken.balanceOf(address(beta)), 20 finney, "beta credit");

        Assert.equal(erc20.balanceOf(address(alpha)), 0 finney, "alpha balance");
        Assert.equal(erc20.balanceOf(address(beta)), 0 finney, "beta balance");
        Assert.equal(creditProvider.totalTokenStock(), 0 finney, "token stock");
    }

    function testRequestWithdrawThenAddPartialFunds() public {
        
        issuer.issueTokens(address(alpha), 100 finney);
        alpha.transfer(address(beta), 20 finney);
        

        (bool success1, ) = address(alpha).call(abi.encodeWithSelector(
                bytes4(keccak256("requestWithdraw()"))));
        (bool success2, ) = address(beta).call(abi.encodeWithSelector(
                bytes4(keccak256("requestWithdraw()"))));
                
        Assert.equal(success1, false, "alpha cant withdraw");
        Assert.equal(success2, false, "beta cant withdraw");

        addErc20Stock(10 finney);

        (bool success3, ) = address(alpha).call(abi.encodeWithSelector(
                bytes4(keccak256("requestWithdraw()"))));
        (bool success4, ) = address(beta).call(abi.encodeWithSelector(
                bytes4(keccak256("requestWithdraw()"))));
        
        Assert.equal(creditToken.balanceOf(address(alpha)), 80 finney, "alpha credit");
        Assert.equal(creditToken.balanceOf(address(beta)), 10 finney, "beta credit");
        
        Assert.equal(erc20.balanceOf(address(alpha)), 0 finney, "alpha balance");
        Assert.equal(erc20.balanceOf(address(beta)), 10 finney, "beta balance");
        Assert.equal(creditProvider.totalTokenStock(), 0 finney, "token stock");
    }

    function testRequestWithdrawThenAddFullFunds() public {
        
        issuer.issueTokens(address(alpha), 100 finney);
        alpha.transfer(address(beta), 20 finney);

        (bool success1, ) = address(alpha).call(abi.encodeWithSelector(
                bytes4(keccak256("requestWithdraw()"))));
        (bool success2, ) = address(beta).call(abi.encodeWithSelector(
                bytes4(keccak256("requestWithdraw()"))));

        addErc20Stock(1 ether);        
        
        (bool success3, ) = address(alpha).call(abi.encodeWithSelector(
                bytes4(keccak256("requestWithdraw()"))));
        (bool success4, ) = address(beta).call(abi.encodeWithSelector(
                bytes4(keccak256("requestWithdraw()"))));

        Assert.equal(creditToken.balanceOf(address(alpha)), 60 finney, "alpha credit");
        Assert.equal(creditToken.balanceOf(address(beta)), 10 finney, "beta credit");

        Assert.equal(erc20.balanceOf(address(alpha)), 20 finney, "alpha balance");
        Assert.equal(erc20.balanceOf(address(beta)), 10 finney, "beta balance");
        Assert.equal(creditProvider.totalTokenStock(), 970 finney, "token stock");
    }

    function testRequestWithdrawSingleIteration() public {
        
        issuer.issueTokens(address(alpha), 100 finney);
        alpha.transfer(address(beta), 20 finney);
        
        (bool success1, ) = address(alpha).call(abi.encodeWithSelector(
                bytes4(keccak256("requestWithdraw()"))));
        (bool success2, ) = address(beta).call(abi.encodeWithSelector(
                bytes4(keccak256("requestWithdraw()"))));

        addErc20Stock(1 ether);

        (bool success3, ) = address(alpha).call(abi.encodeWithSelector(
                bytes4(keccak256("requestWithdraw()"))));
        (bool success4, ) = address(beta).call(abi.encodeWithSelector(
                bytes4(keccak256("requestWithdraw()"))));
        
        Assert.equal(creditToken.balanceOf(address(alpha)), 80 finney, "alpha credit");
        Assert.equal(creditToken.balanceOf(address(beta)), 10 finney, "beta credit");
        
        Assert.equal(erc20.balanceOf(address(alpha)), 0 finney, "alpha balance");
        Assert.equal(erc20.balanceOf(address(beta)), 10 finney, "beta balance");
        Assert.equal(creditProvider.totalTokenStock(), 990 finney, "token stock");
    }

    function testDuplicateRequestWithdrawThenAddFullFunds() public {
        
        issuer.issueTokens(address(alpha), 100 finney);
        alpha.transfer(address(beta), 20 finney);
        
        (bool success1, ) = address(alpha).call(abi.encodeWithSelector(
                bytes4(keccak256("requestWithdraw()"))));
        (bool success2, ) = address(beta).call(abi.encodeWithSelector(bytes4(keccak256("requestWithdraw()"))));
        (bool success3, ) = address(beta).call(abi.encodeWithSelector(bytes4(keccak256("requestWithdraw()"))));

        addErc20Stock(1 ether);

        (bool success4, ) = address(alpha).call(abi.encodeWithSelector(bytes4(keccak256("requestWithdraw()"))));
        (bool success5, ) = address(beta).call(abi.encodeWithSelector(bytes4(keccak256("requestWithdraw()"))));
        (bool success6, ) = address(beta).call(abi.encodeWithSelector(bytes4(keccak256("requestWithdraw()"))));
        
        Assert.equal(creditToken.balanceOf(address(alpha)), 60 finney, "alpha credit");
        Assert.equal(creditToken.balanceOf(address(beta)), 5 finney, "beta credit");

        Assert.equal(erc20.balanceOf(address(alpha)), 20 finney, "alpha balance");
        Assert.equal(erc20.balanceOf(address(beta)), 15 finney, "beta balance");
        Assert.equal(creditProvider.totalTokenStock(), 965 finney, "token stock");
    }

    function testIncreaseQueuedWithdrawRequestValue() public {
        
        issuer.issueTokens(address(alpha), 100 finney);
        alpha.transfer(address(beta), 20 finney);
        
        (bool success2, ) = address(beta).call(abi.encodeWithSelector(bytes4(keccak256("requestWithdraw()"))));

        (bool success,) = address(beta).call(
            abi.encodePacked(
                beta.requestWithdraw.selector,
                abi.encode(15 finney)
            )
        );

        Assert.isFalse(success, "requestWithdraw should fail");
    }

    function testRequestWithdrawThenTransferBalance() public {
        
        issuer.issueTokens(address(alpha), 100 finney);
        alpha.transfer(address(beta), 20 finney);

        (bool success1, ) = address(alpha).call(abi.encodeWithSelector(bytes4(keccak256("requestWithdraw()"))));
        (bool success2, ) = address(beta).call(abi.encodeWithSelector(bytes4(keccak256("requestWithdraw()"))));

        alpha.transfer(address(beta), 80 finney);

        addErc20Stock(1 ether);

        (bool success3, ) = address(alpha).call(abi.encodeWithSelector(bytes4(keccak256("requestWithdraw()"))));
        (bool success4, ) = address(beta).call(abi.encodeWithSelector(bytes4(keccak256("requestWithdraw()"))));
        
        Assert.equal(creditToken.balanceOf(address(alpha)), 0 finney, "alpha credit");
        Assert.equal(creditToken.balanceOf(address(beta)), 90 finney, "beta credit");

        Assert.equal(erc20.balanceOf(address(alpha)), 0 finney, "alpha balance");
        Assert.equal(erc20.balanceOf(address(beta)), 10 finney, "beta balance");
        Assert.equal(creditProvider.totalTokenStock(), 990 finney, "token stock");
    }
}