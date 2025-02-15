USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspGrabValidData
	CreatedBy: Larry Dugger
	Description: This procedure retrieves 60 transactions, added by another process
	Tables: [IFAStorage].[dbo].[ValidData]
	History:
		2015-12-30 - LBD - Created
		2016-05-04 - LBD - Modified, link to IFAStorage, 
			added default OrgId and checktypecode
		2016-06-07 - LBD - Modified, OrgId convert for HEB Test...
		2016-07-07 - LBD - Modified, converted the OrgId to IFAs
		2016-10-03 - LBD - Modified, added in default address and Phone number
		2016-10-10 - LBD - Modified, added in support for PNC data testing
		2019-04-24 - LBD - Modified, Added MTB
		2019-10-08 - LBD - Modified, adjusted to comment out all 
			but HEB and pass HEB Address
*****************************************************************************************/
ALTER   PROCEDURE [dbo].[uspGrabValidData](
	 @piValidDataId INT OUTPUT
	,@piBatchSize INT = 60
	,@piOrgId INT
)AS
BEGIN
drop table if exists #tblGrabValidData
	create table #tblGrabValidData (
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
		INSERT INTO #tblGrabValidData(ValidDataId,OrgId,ProcessKey,ClientRequestId,ClientRequestId2--,CustomerIdentifier
			,FirstName,LastName,AddressLine1,AddressLine2,City,StateAbbv,ZipCode,Country
			,PhoneNumber,EmailAddress,DateOfBirth,IdTypeCode,IdNumber,IdStateAbbv
			,SocialSecurityNumber,ItemTypeCode,ClientItemId,ItemKey,CheckTypeCode
			,ItemDate,CheckAmount,MICR,RoutingNumber,AccountNumber,CheckNumber,Scanned)
		SELECT TOP (@piBatchSize) ValidDataId,OrgId,ProcessKey,ClientRequestId,ClientRequestId2--,CustomerIdentifier
			,FirstName,LastName, AddressLine1,AddressLine2,City,StateAbbv,ZipCode,Country
			,PhoneNumber,EmailAddress,DateOfBirth,IdTypeCode,IdNumber,IdStateAbbv
			,SocialSecurityNumber,ItemTypeCode,ClientItemId,ItemKey
			,CheckTypeCode
			,ItemDate,CheckAmount,MICR,RoutingNumber,AccountNumber,CheckNumber,Scanned
		FROM [Condensed].[dbo].[ValidData] (NOLOCK)
		WHERE ValidDataId >= @piValidDataId
		IF @@ROWCOUNT > 0
			SELECT @piValidDataId = MAX(ValidDataId)
			FROM #tblGrabValidData;
	END
	--ELSE IF @piOrgId = 148795 --PNCTest
	--BEGIN
	--	SET @iTopValidDataId= @piValidDataId+(@piBatchSize-1);
	--	INSERT INTO #tblGrabValidData(ValidDataId,OrgId,ProcessKey,ClientRequestId,ClientRequestId2,CustomerIdentifier
	--		,FirstName,LastName,AddressLine1,AddressLine2,City,StateAbbv,ZipCode,Country
	--		,PhoneNumber,EmailAddress,DateOfBirth,IdTypeCode,IdNumber,IdStateAbbv
	--		,SocialSecurityNumber,ItemTypeCode,ClientItemId,ItemKey,CheckTypeCode
	--		,ItemDate,CheckAmount,MICR,RoutingNumber,AccountNumber,CheckNumber,Scanned)
	--	SELECT TOP (@piBatchSize) PNCDataId,@piOrgId,ProcessKey,ClientRequestId,NULL,CustomerIdentifier
	--		,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
	--		,NULL,NULL,NULL,NULL,NULL,NULL
	--		,NULL,ItemTypeCode,ClientItemId,ItemKey,NULL
	--		,ItemDate,CheckAmount,NULL,RoutingNumber,AccountNumber,CheckNumber,0
	--	FROM [Condensed].[dbo].[PNCData] (NOLOCK)
	--	WHERE PNCDataId >= @piValidDataId;
	--	IF @@ROWCOUNT > 0
	--		SELECT @piValidDataId = MAX(ValidDataId)
	--		FROM #tblGrabValidData;
	--END
	--ELSE IF @piOrgId = 148796 --MTBTest
	--BEGIN
	--	SET @iTopValidDataId= @piValidDataId+(@piBatchSize-1);
	--	INSERT INTO #tblGrabValidData(ValidDataId,OrgId,ProcessKey,ClientRequestId,ClientRequestId2,CustomerIdentifier
	--		,FirstName,LastName,AddressLine1,AddressLine2,City,StateAbbv,ZipCode,Country
	--		,PhoneNumber,EmailAddress,DateOfBirth,IdTypeCode,IdNumber,IdStateAbbv
	--		,SocialSecurityNumber,ItemTypeCode,ClientItemId,ItemKey,CheckTypeCode
	--		,ItemDate,CheckAmount,MICR,RoutingNumber,AccountNumber,CheckNumber
	--		,Scanned,BankAccountNumber,BankRoutingNumber)
	--	SELECT TOP (@piBatchSize) MTBDataId,@piOrgId,ProcessKey,ClientRequestId,NULL,CustomerIdentifier
	--		,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
	--		,NULL,NULL,NULL,NULL,NULL,NULL
	--		,NULL,ItemTypeCode,ClientItemId,ItemKey,CheckTypeCode
	--		,ItemDate,CheckAmount,NULL,RoutingNumber,AccountNumber,CheckNumber
	--		,0,BankAccountNumber,BankRoutingNumber
	--	FROM [Condensed].[dbo].[MTBData] (NOLOCK)
	--	WHERE MTBDataId >= @piValidDataId;
	--	IF @@ROWCOUNT > 0
	--		SELECT @piValidDataId = MAX(ValidDataId)
	--		FROM #tblGrabValidData;
	--END	
	SELECT ValidDataId,OrgId,ProcessKey,ClientRequestId,ClientRequestId2,CustomerIdentifier
		,FirstName,LastName,AddressLine1,AddressLine2,City,StateAbbv,ZipCode,Country,PhoneNumber
		,EmailAddress,DateOfBirth,IdTypeCode,IdNumber,IdStateAbbv
		,SocialSecurityNumber,ItemTypeCode,ClientItemId,ItemKey,CheckTypeCode
		,ItemDate,CheckAmount,MICR,RoutingNumber,AccountNumber,CheckNumber
		,Scanned,BankAccountNumber,BankRoutingNumber
	FROM #tblGrabValidData
	ORDER BY ValidDataId;
END
