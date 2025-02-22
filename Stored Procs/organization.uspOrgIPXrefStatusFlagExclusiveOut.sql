USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspOrgIPXrefStatusFlagExclusiveOut
	CreatedBy: Larry Dugger
	Date: 2015-05-07
	Descr: This procedure will Activate the OrgIPXref (Set StatusFlag to 2)
	Tables: [organization].[OrgIPXref]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-05-07 - LBD - Created
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [organization].[uspOrgIPXrefStatusFlagExclusiveOut](
	 @pnvUserName NVARCHAR(100) = 'N/A'
	,@piOrgIPXrefId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @OrgIPXref table (
		 OrgIPXrefId int
		,OrgId int
		,[IP] nvarchar(255)
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
		);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName nvarchar(128) = N'organization';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [organization].[OrgIPXref]
			SET StatusFlag = 2
				,DateActivated = SYSDATETIME()
				,UserName = @pnvUserName
			OUTPUT deleted.OrgIPXrefId
				,deleted.OrgId
				,deleted.[IP]
				,deleted.StatusFlag
				,deleted.DateActivated
				,deleted.UserName
			INTO @OrgIPXref
			WHERE OrgIPXrefId = @piOrgIPXrefId;
			----Anytime an update occurs we place an original copy in an archive table
			--INSERT INTO [archive].[OrgIPXref](OrgIPXrefId
			--,OrgId
			--	,IP
			--,StatusFlag
			--,DateActivated
			--	,UserName
			--,DateArchived
			--) 
			--SELECT OrgIPXrefId
			--,OrgId
			--	,IP
			--,StatusFlag
			--,DateActivated
			--	,UserName
			--,SYSDATETIME()
			--FROM @OrgIPXref
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piOrgIPXrefId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piOrgIPXrefId = OrgIPXrefId
			FROM @OrgIPXref;
		END
	END
END
