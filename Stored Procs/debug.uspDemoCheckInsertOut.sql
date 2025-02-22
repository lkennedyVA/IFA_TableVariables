USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
   Name: uspDemoCheckInsertOut
   CreatedBy: Larry Dugger
   Descr: This procedure will insert a new record
   Tables: [debug].[DemoCheck]
   
   Functions: [error].[uspLogErrorDetailInsertOut]
   History:
      2019-02-19 - LBD - Created
*****************************************************************************************/
ALTER PROCEDURE [debug].[uspDemoCheckInsertOut](
	 @pnvDemoCheckType NVARCHAR(50) = 'Credit'
	,@pnvExternalCode NVARCHAR(50)
	,@pncRoutingNumber NCHAR(9) = ''
	,@pnvAccountNumber NVARCHAR(50)
	,@piStatusFlag INT 
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@piDemoCheckId INT OUTPUT
)
AS
BEGIN
   SET NOCOUNT ON;

	DECLARE @tblDemoCheck table(
		 DemoCheckId int 
		,DemoCheckTypeId int
		,OrgId int
		,RoutingNumber nchar(9)
		,AccountNumber nvarchar(50)
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);


	DECLARE @iDemoCheckTypeId int = CASE @pnvDemoCheckType WHEN 'Credit' THEN 0 WHEN 'Debit' THEN 1 ELSE 2 END
		,@iOrgId int
		,@iClientOrgId int
		,@iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName nvarchar(128);
	SET @sSchemaName = N'debug';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;

	SELECT @iOrgId = OrgId FROM [organization].[Org] where ExternalCode = @pnvExternalCode;
	SELECT @iClientOrgId = [common].[ufnOrgClientId](@iOrgId);
	SET @piDemoCheckId = NULL;

	SELECT @piDemoCheckId = DemoCheckId
	FROM [debug].[DemoCheck]
	WHERE DemoCheckTypeId = @iDemoCheckTypeId
		and OrgId = @iClientOrgId
		and RoutingNumber = @pncRoutingNumber
		and AccountNumber = @pnvAccountNumber;

	IF @piDemoCheckId is NULL
	BEGIN TRANSACTION
	BEGIN TRY
		INSERT INTO [debug].[DemoCheck](DemoCheckTypeId, OrgId, RoutingNumber, AccountNumber, StatusFlag, DateActivated, UserName)
		SELECT @iDemoCheckTypeId
			,@iClientOrgId
			,@pncRoutingNumber
			,@pnvAccountNumber
			,@piStatusFlag
			,SYSDATETIME()
			,@pnvUserName; 
		SET @piDemoCheckId = @@IDENTITY;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @piDemoCheckId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
	BEGIN
		COMMIT TRANSACTION;
		SELECT @piDemoCheckId as DemoCheckId
	END
END
