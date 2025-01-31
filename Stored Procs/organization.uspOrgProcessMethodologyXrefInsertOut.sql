USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspOrgProcessMethodologyXrefInsertOut
	CreatedBy: Larry Dugger
	Descr: This procedure will insert a new record, note this is currently set
		at the Client OrgType Level only.
		Returns -3 when the org provided is not a client type.

	Tables: [organization].[OrgProcessMethodologyXref]
   
	Procedures: [error].[uspLogErrorDetailInsertOut]

	History:
		2020-01-22 - LBD - Created
*****************************************************************************************/
ALTER   PROCEDURE [organization].[uspOrgProcessMethodologyXrefInsertOut](
	@piOrgClientId INT
	,@piProcessMethodologyId INT
	,@piStatusFlag INT  
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@piOrgProcessMethodologyXrefId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @OrgProcessMethodologyXref table (
		OrgProcessMethodologyXrefId int
		,OrgId int
		,ProcessMethodologyId int
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
		);
	DECLARE @iOrgClientId int = @piOrgClientId
		,@iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName sysname = OBJECT_SCHEMA_NAME(@@PROCID);

	IF EXISTS (SELECT 'X' FROM [organization].[Org] o
				INNER JOIN [organization].[OrgType] ot on o.OrgTypeId = ot.OrgTypeId
				WHERE o.OrgId = @iOrgClientId
					AND ot.[Name] = 'Client')
	BEGIN
		SET @iCurrentTransactionLevel = @@TRANCOUNT;
		BEGIN TRANSACTION
		BEGIN TRY
			INSERT INTO [organization].[OrgProcessMethodologyXref]
				OUTPUT inserted.OrgProcessMethodologyXrefId
				,inserted.OrgId
				,inserted.ProcessMethodologyId
				,inserted.StatusFlag
				,inserted.DateActivated
				,inserted.UserName
				INTO @OrgProcessMethodologyXref
			SELECT @iOrgClientId
				,@piProcessMethodologyId
				,@piStatusFlag
				,SYSDATETIME()
				,@pnvUserName; 
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
				ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piOrgProcessMethodologyXrefId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piOrgProcessMethodologyXrefId = OrgProcessMethodologyXrefId
			FROM @OrgProcessMethodologyXref
		END
	END
	ELSE
		SELECT @piOrgProcessMethodologyXrefId = -3
END
