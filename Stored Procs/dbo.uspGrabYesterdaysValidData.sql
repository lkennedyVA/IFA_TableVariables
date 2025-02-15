USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspGrabValidYesterdaysData
	CreatedBy: Larry Dugger
	Description: This procedure retrieves yesterdays transactions, added by another process
	Tables: [Condensed].[dbo].[ValidData]
	History:
		2016-11-15 - LBD - Created
		2019-04-24 - LBD - Modified, Added MTB
		2019-10-08 - LBD - Modified, commented out all but HEB, adjusted HEB to return
			actual address.
*****************************************************************************************/
ALTER   PROCEDURE [dbo].[uspGrabYesterdaysValidData](
	 @piValidDataId INT OUTPUT
	,@piOrgId INT
)AS
BEGIN
drop table if exists #tblGrabYesterdaysValidData
	create table #tblGrabYesterdaysValidData(
		 ValidDataId int
		,OrgId int
		,ProcessKey nvarchar(25)
		,ClientRequestId nvarchar(50)
		,ClientRequestId2 nvarchar(50)
		,CustomerIdentifier nvarchar(50)	
		,FirstName nvarchar(50)
		,LastName nvarchar(50)
		,AddressLine1 nvarchar(150)
		,AddressLine2 nvarchar(150)
		,City nvarchar(100)
		,StateAbbv nchar(2)
		,ZipCode nvarchar(9)
		,Country nvarchar(50)
		,PhoneNumber nvarchar(10)
		,EmailAddress nvarchar(100)
		,DateOfBirth DATE
		,IdTypeCode nvarchar(25)
		,IdNumber nvarchar(50)
		,IdStateAbbv nchar(2) 		
		,SocialSecurityNumber nvarchar(9)
		,ItemTypeCode nvarchar(25)
		,ClientItemId nvarchar(50) 
		,ItemKey nvarchar(25)
		,CheckTypeCode nvarchar(25)
		,ItemDate datetime
		,CheckAmount money
		,MICR nvarchar(255)
		,RoutingNumber nchar(9)
		,AccountNumber nvarchar(50)
		,CheckNumber nvarchar(50)
		,Scanned bit
		,BankAccountNumber nvarchar(50)
		,BankRoutingNumber nchar(9)
	);
	DECLARE @iTopValidDataId int;
	IF @piOrgId = 3719	--HEB 
	BEGIN
		INSERT INTO #tblGrabYesterdaysValidData(ValidDataId,OrgId,ProcessKey,ClientRequestId,ClientRequestId2,CustomerIdentifier
			,FirstName,LastName,AddressLine1,AddressLine2,City,StateAbbv,ZipCode,Country
			,PhoneNumber,EmailAddress,DateOfBirth,IdTypeCode,IdNumber,IdStateAbbv
			,SocialSecurityNumber,ItemTypeCode,ClientItemId,ItemKey,CheckTypeCode
			,ItemDate,CheckAmount,MICR,RoutingNumber,AccountNumber,CheckNumber,Scanned)
		SELECT ValidDataId,OrgId,ProcessKey,ClientRequestId,ClientRequestId2,CustomerIdentifier
			,FirstName,LastName, AddressLine1,AddressLine2,City,StateAbbv,ZipCode,Country 
			,PhoneNumber,EmailAddress,DateOfBirth,IdTypeCode,IdNumber,IdStateAbbv
			,SocialSecurityNumber,ItemTypeCode,ClientItemId,ItemKey
			,CheckTypeCode
			,ItemDate,CheckAmount,MICR,RoutingNumber,AccountNumber,CheckNumber,Scanned
		FROM [Condensed].[dbo].[ValidData]
		WHERE datediff(day,getdate()-1, TranDate) = 0
		IF @@ROWCOUNT > 0
			SELECT @piValidDataId = MAX(ValidDataId)
			FROM #tblGrabYesterdaysValidData;
	END
	--ELSE IF @piOrgId = 148795 --PNCTest
	--BEGIN
	--	INSERT INTO #tblGrabYesterdaysValidData(ValidDataId,OrgId,ProcessKey,ClientRequestId,ClientRequestId2,CustomerIdentifier
	--		,FirstName,LastName,AddressLine1,AddressLine2,City,StateAbbv,ZipCode,Country
	--		,PhoneNumber,EmailAddress,DateOfBirth,IdTypeCode,IdNumber,IdStateAbbv
	--		,SocialSecurityNumber,ItemTypeCode,ClientItemId,ItemKey,CheckTypeCode
	--		,ItemDate,CheckAmount,MICR,RoutingNumber,AccountNumber,CheckNumber,Scanned)
	--	SELECT PNCDataId,@piOrgId,ProcessKey,ClientRequestId,NULL,CustomerIdentifier
	--		,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
	--		,NULL,NULL,NULL,NULL,NULL,NULL
	--		,NULL,ItemTypeCode,ClientItemId,ItemKey,NULL
	--		,ItemDate,CheckAmount,NULL,RoutingNumber,AccountNumber,CheckNumber,0
	--	FROM [Condensed].[dbo].[PNCData]
	--	WHERE datediff(day,getdate()-1, TranDate) = 0
	--	IF @@ROWCOUNT > 0
	--		SELECT @piValidDataId = MAX(ValidDataId)
	--		FROM #tblGrabYesterdaysValidData;
	--END
	--ELSE IF @piOrgId = 148796 --MTBTest
	--BEGIN
	--	INSERT INTO #tblGrabYesterdaysValidData(ValidDataId,OrgId,ProcessKey,ClientRequestId,ClientRequestId2,CustomerIdentifier
	--		,FirstName,LastName,AddressLine1,AddressLine2,City,StateAbbv,ZipCode,Country
	--		,PhoneNumber,EmailAddress,DateOfBirth,IdTypeCode,IdNumber,IdStateAbbv
	--		,SocialSecurityNumber,ItemTypeCode,ClientItemId,ItemKey,CheckTypeCode
	--		,ItemDate,CheckAmount,MICR,RoutingNumber,AccountNumber,CheckNumber
	--		,Scanned,BankAccountNumber,BankRoutingNumber)
	--	SELECT MTBDataId,@piOrgId,ProcessKey,ClientRequestId,NULL,CustomerIdentifier
	--		,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
	--		,NULL,NULL,NULL,NULL,NULL,NULL
	--		,NULL,ItemTypeCode,ClientItemId,ItemKey,CheckTypeCode
	--		,ItemDate,CheckAmount,NULL,RoutingNumber,AccountNumber,CheckNumber
	--		,0,BankAccountNumber,BankRoutingNumber
	--	FROM [Condensed].[dbo].[MTBData] 
	--	WHERE datediff(day,getdate()-1, TranDate) = 0
	--	IF @@ROWCOUNT > 0
	--		SELECT @piValidDataId = MAX(ValidDataId)
	--		FROM #tblGrabYesterdaysValidData;
	--END	
	SELECT ValidDataId,OrgId,ProcessKey,ClientRequestId,ClientRequestId2,CustomerIdentifier
		,FirstName,LastName,AddressLine1,AddressLine2,City,StateAbbv,ZipCode,Country,PhoneNumber
		,EmailAddress,DateOfBirth,IdTypeCode,IdNumber,IdStateAbbv
		,SocialSecurityNumber,ItemTypeCode,ClientItemId,ItemKey,CheckTypeCode
		,ItemDate,CheckAmount,MICR,RoutingNumber,AccountNumber,CheckNumber
		,Scanned,BankAccountNumber,BankRoutingNumber
	FROM #tblGrabYesterdaysValidData
	ORDER BY ValidDataId;
END
