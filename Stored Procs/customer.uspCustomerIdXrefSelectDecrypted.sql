USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspCustomerIdXrefSelectDecrypted
	CreatedBy: Larry Dugger
	Description: This procedure will return customerid

	Tables: [customer].[CustomerIdXref]
		,[common].[IdType]

	Functions:

	History:
		2015-05-07 - LBD - Created
		2019-11-13 - LBD - Modified, removed unused variables
*****************************************************************************************/
ALTER   PROCEDURE [customer].[uspCustomerIdXrefSelectDecrypted]
	 @pnvFirstName NVARCHAR(50) = N''
	,@pnvLastName NVARCHAR(50) = N''
	,@piIdTypeId INT = -1
	,@piOrgId INT = -1
	,@pbiCustomerId BIGINT = -1
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @UpOrgList table(
		 LevelId int
		,ChildId int
		,OrgId int
		,OrgName nvarchar(255)
		,ExternalCode nvarchar(50)
		,TypeId int
		,[Type] nvarchar(50)
		,StatusFlag int
		,DateActivated datetime2(7)
	);
	DECLARE @iOrgId int = @piOrgId
		,@nvFirstName nvarchar(50) = @pnvFirstName
		,@nvLastName nvarchar(50) = @pnvLastName
		,@iIdTypeId int = @piIdTypeId
		,@biCustomerId bigint = @pbiCustomerId
		,@iOrgDimensionId int = [common].[ufnDimension]('Organization')
		,@iErrorDetailId int
		,@sSchemaName nvarchar(128) = N'customer';

	INSERT INTO @UpOrgList(LevelId,ChildId,OrgId,OrgName,ExternalCode,TypeId,[Type],StatusFlag,DateActivated)
	SELECT LevelId,ChildId,OrgId,OrgName,ExternalCode,TypeId,[Type],StatusFlag,DateActivated
	FROM [common].[ufnUpDimensionByOrgIdILTF](@iOrgId,@iOrgDimensionId)
	ORDER BY ChildId, OrgId;

	OPEN SYMMETRIC KEY VALIdSymKey DECRYPTION BY ASYMMETRIC KEY [VALIDASYMKEY];
	SELECT c.CustomerId, c.FirstName, c.LastName, cix.CustomerIdXrefId, cix.IdTypeId, cix.IdStateId, 
		CONVERT(NVARCHAR(50),DECRYPTBYKEY(cix.IdEncrypted)) Id,
		cix.IdMac, cix.Last4, cix.OrgId, cix.StatusFlag, cix.DateActivated, cix.IdMac64
	FROM [customer].[Customer] c
	INNER JOIN [customer].[CustomerIdXref] cix on c.CustomerId = cix.CustomerId
	CROSS APPLY @UpOrgList uol
	WHERE (ISNULL(@nvFirstName,N'') = N''
			OR c.FirstName = @nvFirstName)
		AND  (ISNULL(@nvLastName,N'') = N''
			OR c.LastName = @nvLastName)
		AND (ISNULL(@biCustomerId,-1) = -1
			OR cix.CustomerId = @biCustomerId)
		AND (ISNULL(@iOrgId,-1) = -1
			OR uol.OrgId = @iOrgId)
		AND (ISNULL(@iIdTypeId,-1) = -1
			OR cix.IdTypeId = @iIdTypeId);
	CLOSE SYMMETRIC KEY VALIdSymKey;
END
