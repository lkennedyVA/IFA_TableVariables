USE [IFA]
GO
/****** Object:  StoredProcedure [command].[uspOrgIPXrefInsert]    Script Date: 1/2/2025 6:07:29 AM ******/
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
		2017-11-21 - LBD - Created
*****************************************************************************************/
ALTER PROCEDURE [command].[uspOrgIPXrefInsert](
	 @piOrgId INT
	,@pnvIP NVARCHAR(255)
	,@piStatusFlag INT  
	,@pnvUserName NVARCHAR(100) = 'N/A'
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
		,@sSchemaName nvarchar(128) = N'command';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN TRANSACTION
	BEGIN TRY
		INSERT INTO [organization].[OrgIPXref]
			OUTPUT inserted.OrgIPXrefId
			,inserted.OrgId
			,inserted.[IP]
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
		THROW
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
	BEGIN
		COMMIT TRANSACTION;
		SELECT ox.OrgIPXrefId, ox.OrgId, o.Name AS OrgName, o.OrgTypeId 
			,ox.[IP], ox.StatusFlag, ox.DateActivated, ox.UserName
		FROM @OrgIPXref ox
		INNER JOIN [organization].[Org] o on ox.OrgId = o.OrgId
	END
END
