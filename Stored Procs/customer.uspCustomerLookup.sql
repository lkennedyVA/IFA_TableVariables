USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [uspCustomerLookup]
	CreatedBy: Larry Dugger
	Description: Based on the OrgId and the IdDecrypted passed in we retrieve the 
		customer, then we retrieve the associated IDs for that customer, along with
		the customr particulars...address.
	Tables: [customer].[CustomerIdXref]
		[common].[IdType]
	History:
		2015-05-26 - LBD - Created
		2015-06-16 - LBD - Modified, return nothing if not found
		2018-02-01 - LBD - Modified, adjusted to meet API (bridge) needs
		2019-10-25 - LBD - Modified, added support for new IdMac64 --commented out
			,corrected the CustomerIdType reference
		2019-11-05 - LBD - Modified, created defaults for NULL conditions
		2019-11-13 - LBD - Modified, activated IdMac64, remove defaults because
			Hal has confirmed all data is being passed in.
		2019-11-25 - LBD - Modified, added defaults back in. 'HEB uses SSN' as primary
		2020-09-13 - LBD - Since this is used by HEB I will default PrimaryId to SSN
		2025-01-13 - LXK - Replaced table variables with local temp tables
*****************************************************************************************/
ALTER   PROCEDURE [customer].[uspCustomerLookup](
	@ptblId ifa.CustomerIdType READONLY 
) 
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @iErrorDetailId int
		,@sSchemaName nvarchar(128) = OBJECT_SCHEMA_NAME(@@PROCID)
		,@vbIdMac varbinary(50) = 0x
		,@iCnt int = 0
		,@bPrimaryId bit = 0;
	DECLARE @tblCustomerIdType [ifa].[IdType];

	drop table if exists #CustomerLookup
	create table #CustomerLookup table(
		 CustomerId bigint not null
		,OrgId int null
		,FirstName nvarchar(50) null
		,LastName nvarchar(50) null
		,DateOfBirth date null
		,WorkPhone nvarchar(10) null
		,CellPhone nvarchar(10) null
		,Email nvarchar(100) null
		,DateEnrolled date null
		,StatusFlag int null
		,DateActivated datetime2(7) null
		,AddressId bigint null
		,Address1 nvarchar(150) null
		,Address2 nvarchar(150) null
		,City nvarchar(100) null
		,StateId int null
		,StateAbbv nvarchar(25) null
		,ZipCode nvarchar(9) null
		,Country nvarchar(50) null
		,Longitude real null
		,Latitude real null
		,AddressStatusFlag int null
		,AddressDateActivated datetime2(7) null
	);

	INSERT INTO @tblCustomerIdType([OrgId], [Id], [IdTypeId], [IdTypeCode], [IdStateId], [IdStateCode], [PrimaryId], [IdMac], [IdMAc64])
	SELECT i.[OrgId], i.[Id], it.[IdTypeId], it.Code, s.[StateId], s.Code	--,[common].[ufnPrimaryIdType](ISNULL(i.[OrgId],42)) 2020-09-13
		,3	--2020-09-13
		,[ifa].[ufnMAC](i.[Id])
		,[ifa].[ufnIdMAC64](it.[IdTypeId], i.[OrgId], s.[StateId], i.[Id])
	FROM @ptblId i
	INNER JOIN [common].[IdType] it on ISNULL(i.IdTypeCode,N'3') = it.Code
	INNER JOIN [common].[State] s on ISNULL(i.IdStateCode,N'Un') = s.Code;

	SELECT @bPrimaryId = CASE WHEN PrimaryId = IdTypeId THEN 1 ELSE 0 END
	FROM @tblCustomerIdType;

	BEGIN TRY
		----Retrieve all customers for this id set....
		--OPEN SYMMETRIC KEY VALIDSymKey DECRYPTION BY asymmetric key VALIDAsymKey;
		WITH Customer_CTE (CustomerId,DateActivated,OrgId,Id,IdTypeCode,IdStateCode,Stateid,IdTypeId,IdMac,StatusFlag)
			AS (SELECT cix.CustomerId
				,cix.DateActivated 
				,ti.OrgId
				,ti.Id
				,ti.IdTypeCode
				,ti.IdStateCode
				,cit.IdStateId
				,cit.IdTypeId
				,cit.IdMac 
				,cix.StatusFlag
			FROM @ptblId ti
			INNER JOIN @tblCustomerIdType  cit ON ISNULL(ti.IdTypeCode,'3') = cit.IdTypeCode
												AND ISNULL(ti.IdStateCode,'Un') = cit.IdStateCode
			INNER JOIN [customer].[CustomerIdXref] cix ON cit.IdMac64 = cix.IdMac64 --2019-11-13
			WHERE @bPrimaryId = 1
				AND cix.StatusFlag = 1
		)
		--GATHER THE CUSTOMER RECORDS
		INSERT INTO #CustomerLookup (CustomerId,FirstName,LastName,DateOfBirth,WorkPhone,CellPhone,Email
			,DateEnrolled,StatusFlag,DateActivated,AddressId,Address1,Address2,City
			,StateAbbv,ZipCode,Latitude,Longitude,Country,AddressStatusFlag,AddressDateActivated)
		SELECT distinct c.CustomerId, c.FirstName, c.LastName, c.DateOfBirth, c.WorkPhone, c.CellPhone, 
			c.Email, c.DateEnrolled, c.StatusFlag, c.DateActivated,
			a.AddressId, a.Address1, a.Address2, a.City, a.StateCode, CASE WHEN a.ZipCode IS NULL THEN NULL ELSE RTRIM(LTRIM(a.ZipCode)) + ISNULL(RTRIM(LTRIM(a.ZipCodeLast4)),'') END as ZipCode, 
			a.Latitude,a.Longitude,a.Country, a.AddressStatusFlag, a.AddressDateActivated
		FROM Customer_CTE cc
		--Only one Id will be returned 
		----Reduce to the most common or oldest if all are the same count
		--INNER JOIN (SELECT TOP 1 CustomerId, COUNT(*) as Cnt, Max(DateActivated) as MaxDt
		--					   FROM Customer_CTE
		--					   GROUP BY CustomerId
		--					   ORDER BY Cnt DESC, MaxDt Asc) co ON cc.CustomerId = co.CustomerId	 
		INNER JOIN [customer].[Customer] c on cc.CustomerId = c.CustomerId
		LEFT OUTER JOIN (SELECT cax.CustomerId, a.AddressId, a.Address1, a.Address2, a.City, a.StateId,
							s.Code as StateCode, a.ZipCode, a.ZipCodeLast4, a.Country,a.Latitude,a.Longitude,
							a.StatusFlag AddressStatusFlag, a.DateActivated AddressDateActivated
						FROM [CustomerAddressXref] cax 
						INNER JOIN  [common].[Address] a on cax.AddressId = a.AddressId
						INNER JOIN [common].[State] s on a.StateId = s.StateId) a on cc.CustomerId = a.CustomerId;

		--CLOSE SYMMETRIC KEY VALIDSymKey;

	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		THROW
	END CATCH;
	SELECT CustomerId,FirstName,LastName,DateOfBirth,WorkPhone,CellPhone,Email
			,DateEnrolled,StatusFlag,DateActivated,AddressId,Address1,Address2,City,StateId
			,StateAbbv,ZipCode,Latitude,Longitude,Country,AddressStatusFlag,AddressDateActivated
	FROM #CustomerLookup;
END
