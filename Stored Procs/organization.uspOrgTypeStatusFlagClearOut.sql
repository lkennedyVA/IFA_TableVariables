USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspOrgTypeStatusFlagClearOut
	CreatedBy: Larry Dugger
	Date: 2015-05-07
	Descr: This procedure will DeActivate the OrgType (Clear StatusFlag)
	Tables: [organization].[OrgType]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-05-07 - LBD - Created
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [organization].[uspOrgTypeStatusFlagClearOut](
	 @pnvUserName NVARCHAR(100) = 'N/A'
	,@piOrgTypeId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @OrgType table (
		 OrgTypeId int
		,Code nvarchar(25)
		,[Name] nvarchar(50)
		,Descr nvarchar(255)
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
			UPDATE [organization].[OrgType]
			SET StatusFlag = 0
				,DateActivated = SYSDATETIME()
				,UserName = @pnvUserName
			OUTPUT deleted.OrgTypeId
				,deleted.Code
				,deleted.[Name]
				,deleted.Descr
				,deleted.StatusFlag
				,deleted.DateActivated
				,deleted.UserName
			INTO @OrgType
			WHERE OrgTypeId = @piOrgTypeId;
			----Anytime an update occurs we place an original copy in an archive table
			--INSERT INTO [archive].[OrgType](OrgTypeId
			--,Code
			--,Name
			--,Descr
			--,StatusFlag
			--,DateActivated
			--	,UserName
			--,DateArchived
			--) 
			--SELECT OrgTypeId
			--,Code
			--,Name
			--,Descr
			--,StatusFlag
			--,DateActivated
			--	,UserName
			--,SYSDATETIME()
			--FROM @OrgType
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piOrgTypeId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piOrgTypeId = OrgTypeId
			FROM @OrgType;
		END
	END
END
