USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspDeviceInfoInsertOut
	CreatedBy: Larry Dugger
	Date: 2015-05-07
	Descr: This procedure will insert a new record
	Tables: [ifa].[Device] 
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-06-17 - LBD - Created
*****************************************************************************************/
ALTER PROCEDURE [ifa].[uspDeviceInfoInsertOut](
	 @pbiProcessId BIGINT
	,@ptblDeviceInfo [ifa].[DeviceInfoType] READONLY
	,@piStatusFlag INT
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@pbiDeviceInfoId BIGINT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @Device table (
		 DeviceId bigint
		,ProcessId bigint
		,UDID nvarchar(100)
		,IPaddress nvarchar(100)
		,Latitude float
		,Longitude float
		,DeviceType nvarchar(100)
		,OSVersion nvarchar(100)
		,MobileNumber nvarchar(100)
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
		);
	DECLARE @iStatusFlag int = [common].[ufnStatusFlag]('Active')
		,@iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName nvarchar(128) = N'ifa';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN TRANSACTION
	BEGIN TRY
		--INSERT What is new
		INSERT INTO [ifa].[Device]
			OUTPUT inserted.DeviceId
				,inserted.ProcessId
				,inserted.UDID
				,inserted.IPaddress
				,inserted.Latitude
				,inserted.Longitude
				,inserted.DeviceType
				,inserted.OSVersion
				,inserted.MobileNumber
				,inserted.StatusFlag
				,inserted.DateActivated
				,inserted.UserName
			INTO @Device
		SELECT @pbiProcessId
			,UDID
			,IPaddress
			,Latitude
			,Longitude
			,DeviceType
			,OSVersion
			,MobileNumber
			,@piStatusFlag
			,SYSDATETIME()
			,@pnvUserName
		FROM @ptblDeviceInfo;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @pbiDeviceInfoId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
		THROW;
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
	BEGIN
		COMMIT TRANSACTION;
		SELECT @pbiDeviceInfoId = MAX(DeviceId)
		FROM @Device;
	END
END
