USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspOrgIPXrefInsertOut
	CreatedBy: Larry Dugger
	Descr: This procedure will insert a new record
	Tables: [organization].[OrgIPXref]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-05-07 - LBD - Created
		2017-11-07 - LBD - Modified, added THROW to the CATCH
*****************************************************************************************/
ALTER PROCEDURE [organization].[uspOrgIPXrefInsertOut](
	 @piOrgId INT
	,@pnvIP NVARCHAR(255)
	,@piStatusFlag INT  
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@piOrgIPXrefId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @OrgIPXref table (
		 OrgIPXrefId int
		,OrgId int
		,IP nvarchar(255)
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName nvarchar(128) = N'organization';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN TRANSACTION
	BEGIN TRY
		INSERT INTO [organization].[OrgIPXref]
			OUTPUT inserted.OrgIPXrefId
			,inserted.OrgId
			,inserted.IP
			,inserted.StatusFlag
			,inserted.DateActivated
			,inserted.UserName
			INTO @OrgIPXref
		SELECT @piOrgId
			,@pnvIP
			,@piStatusFlag
			,SYSDATETIME()
			,@pnvUserName; 
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @piOrgIPXrefId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
		THROW
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
	BEGIN
		COMMIT TRANSACTION;
		SELECT @piOrgIPXrefId = OrgIPXrefId
		FROM @OrgIPXref
	END
END
